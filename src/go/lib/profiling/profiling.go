/*
   Copyright (c) 2017, Percona LLC and/or its affiliates. All rights reserved.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU Affero General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU Affero General Public License for more details.

   You should have received a copy of the GNU Affero General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>
*/

package profiling

import (
	"github.com/percona/pmgo"
	"gopkg.in/mgo.v2"
	"gopkg.in/mgo.v2/bson"
)

func Enable(url string) error {
	session, err := createSession(url)
	if err != nil {
		return err
	}
	defer session.Close()

	err = profile(session.DB(""), 2)
	if err != nil {
		return err
	}

	return nil
}

func Disable(url string) error {
	session, err := createSession(url)
	if err != nil {
		return err
	}
	defer session.Close()

	err = profile(session.DB(""), 0)
	if err != nil {
		return err
	}

	return nil
}

func Drop(url string) error {
	session, err := createSession(url)
	if err != nil {
		return err
	}
	defer session.Close()

	return session.DB("").C("system.profile").DropCollection()
}

func profile(db pmgo.DatabaseManager, v int) error {
	result := struct {
		Was       int
		Slowms    int
		Ratelimit int
	}{}
	return db.Run(
		bson.M{
			"profile": v,
		},
		&result,
	)
}

func createSession(url string) (pmgo.SessionManager, error) {
	dialInfo, err := pmgo.ParseURL(url)
	if err != nil {
		return nil, err
	}
	dialer := pmgo.NewDialer()

	session, err := dialer.DialWithInfo(dialInfo)
	if err != nil {
		return nil, err
	}

	session.SetMode(mgo.Eventual, true)
	return session, nil
}
