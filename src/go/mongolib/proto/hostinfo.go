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

package proto

import "go.mongodb.org/mongo-driver/bson/primitive"

type Extra struct {
	LibcVersion      string  `bson:"libcVersion"`
	PageSize         float64 `bson:"pageSize"`
	VersionSignature string  `bson:"versionSignature"`
	NumPages         float64 `bson:"numPages"`
	VersionString    string  `bson:"versionString"`
	CpuFeatures      string  `bson:"cpuFeatures"`
	CpuFrequencyMHz  string  `bson:"cpuFrequencyMHz"`
	KernelVersion    string  `bson:"kernelVersion"`
	MaxOpenFiles     float64 `bson:"maxOpenFiles"`
}

type Os struct {
	Type    string `bson:"type"`
	Version string `bson:"version"`
	Name    string `bson:"name"`
}

type System struct {
	CurrentTime primitive.DateTime `bson:"currentTime"`
	Hostname    string             `bson:"hostname"`
	MemSizeMB   float64            `bson:"memSizeMB"`
	NumCores    float64            `bson:"numCores"`
	NumaEnabled bool               `bson:"numaEnabled"`
	CpuAddrSize float64            `bson:"cpuAddrSize"`
	CpuArch     string             `bson:"cpuArch"`
}

// HostInfo has exported field for the 'hostInfo' command plus some other
// fields like Database/Collections count. We are setting those fields into
// a separated function
type HostInfo struct {
	Extra  *Extra  `bson:"extra"`
	Os     *Os     `bson:"os"`
	System *System `bson:"system"`
	ID     int
}
