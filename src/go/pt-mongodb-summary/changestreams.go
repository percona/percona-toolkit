// This program is copyright 2016-2026 Percona LLC and/or its affiliates.
//
// THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
//
// This program is free software; you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 2.
//
// You should have received a copy of the GNU General Public License, version 2
// along with this program; if not, see <https://www.gnu.org/licenses/>.

package main

import (
	"context"
	"fmt"

	log "github.com/sirupsen/logrus"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

type changeStreamsInfo struct {
	PreAndPostImagesExpire string
	Readable               bool
	PreImageDocs           *int64
	PreImageBytes          *int64
	PreImageStorageBytes   *int64
}

func getChangeStreams(ctx context.Context, client *mongo.Client, snap *snapshot, hi *hostInfo, b *budget, g *gaps) *changeStreamsInfo {
	return changeStreamsFrom(snap, hi, g, func() (bson.Raw, error) {
		cctx, cancel := b.ctx(ctx, nodeCallTimeout)
		defer cancel()

		return runRaw(cctx, client, "admin", bson.D{{Key: "getClusterParameter", Value: "changeStreamOptions"}})
	})
}

func changeStreamsFrom(snap *snapshot, hi *hostInfo, g *gaps, getClusterParameter func() (bson.Raw, error)) *changeStreamsInfo {
	if hi == nil || hi.IsArbiter || majorVersion(hi.Version) < 6 {
		return nil
	}

	if !snap.isMongos() && snap.IsMaster.SetName == nil {
		return nil
	}

	if cs := preImagesFromServerStatus(snap.ServerStatus); cs != nil {
		return cs
	}

	reply, err := getClusterParameter()
	if errorCode(err) == codeUnauthorized {
		log.Infof("cannot get change stream options: %s", err)

		return &changeStreamsInfo{}
	}

	if err != nil {
		g.add("Change Streams", "Change Streams", "getClusterParameter: clusterManager", err)

		return nil
	}

	expire, ok := expireAfterSeconds(reply)
	if !ok {
		g.note("Change Streams", "Change Streams", "getClusterParameter returned no changeStreamOptions", false)

		return nil
	}

	return &changeStreamsInfo{PreAndPostImagesExpire: expire, Readable: true}
}

func preImagesFromServerStatus(ss bson.Raw) *changeStreamsInfo {
	doc, ok := rawDoc(ss, "changeStreamPreImages")
	if !ok {
		return nil
	}

	docs, hasDocs := rawInt64(doc, "numDocs")
	expire, hasExpire := expireValue(doc)

	if !hasDocs && !hasExpire {
		return nil
	}

	cs := &changeStreamsInfo{PreAndPostImagesExpire: "off", Readable: true}
	if hasExpire {
		cs.PreAndPostImagesExpire = expire
	}

	if hasDocs {
		cs.PreImageDocs = &docs
	}

	if v, ok := rawInt64(doc, "totalBytes"); ok {
		cs.PreImageBytes = &v
	}

	if v, ok := rawInt64(doc, "storageSize"); ok {
		cs.PreImageStorageBytes = &v
	}

	return cs
}

func expireAfterSeconds(reply bson.Raw) (string, bool) {
	params, ok := rawValue(reply, "clusterParameters")
	if !ok {
		return "", false
	}

	arr, ok := params.ArrayOK()
	if !ok {
		return "", false
	}

	values, err := arr.Values()
	if err != nil {
		return "", false
	}

	for _, v := range values {
		p, ok := v.DocumentOK()
		if !ok {
			continue
		}

		if id, _ := rawString(p, "_id"); id != "changeStreamOptions" {
			continue
		}

		if images, ok := rawDoc(p, "preAndPostImages"); ok {
			return expireValue(images)
		}
	}

	return "", false
}

func expireValue(doc bson.Raw) (string, bool) {
	if s, ok := rawString(doc, "expireAfterSeconds"); ok {
		return s, true
	}

	if n, ok := rawInt64(doc, "expireAfterSeconds"); ok {
		return fmt.Sprintf("%d s", n), true
	}

	return "", false
}

func (c *changeStreamsInfo) PreImages() string {
	if c.PreImageDocs == nil {
		return ""
	}

	if *c.PreImageDocs == 0 && c.PreAndPostImagesExpire == "off" {
		return "not in use"
	}

	s := fmt.Sprintf("%d docs", *c.PreImageDocs)
	if c.PreImageBytes != nil {
		s += ", " + formatBytes(*c.PreImageBytes) + " data"
	}

	if c.PreImageStorageBytes != nil {
		s += ", " + formatBytes(*c.PreImageStorageBytes) + " on disk"
	}

	return s
}
