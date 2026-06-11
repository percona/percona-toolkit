// This program is copyright 2017-2026 Percona LLC and/or its affiliates.
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

package config

// Config specifies a list of configuration files to read.
// Following the Percona Toolkit specification:
//  1. Position: The --config option must be the first argument on the command line.
//     Specifying it elsewhere will result in an error.
//  2. Syntax: It does not support the equal sign.
//     Correct: --config /path/to/file. Incorrect: --config=/path/to/file.
//  3. Multiple files: You can provide a comma-separated list of files.
//  4. Disabling configs: To prevent the tool from reading any configuration files
//     at all (including system-wide and user defaults), specify an empty string: --config ”.
//  5. Precedence: If specified, only the provided files are read. If omitted,
//     the tool searches for default configuration files in standard locations.
type ConfigFlag struct {
	Config []string `name:"config" help:"List of Percona Toolkit configuration file(s) separated by comma without equal sign. Must be a first flag. Uses default config file locations if not specified."`
}

// VersionFlag adds a --version flag that prints the tool version and exits.
// Embed this struct into the CLI struct to enable version reporting.
type VersionFlag struct {
	Version bool `name:"version"`
}

// VersionCheckFlag adds a --version-check / --no-version-check flag that controls
// whether the tool checks for a newer version of itself on startup.
// Enabled by default; disable with --no-version-check.
// Embed this struct into the CLI struct to enable version check control:
type VersionCheckFlag struct {
	VersionCheck bool `name:"version-check" negatable:"" default:"true"`
}
