// This program is copyright 2023-2026 Percona LLC and/or its affiliates.
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

package regex

import (
	"testing"

	"github.com/percona/percona-toolkit/src/go/pt-galera-log-explainer/types"
)

func TestApplicativeRegex(t *testing.T) {
	tests := []regexTest{
		{
			log: "2001-01-01  1:01:01 0 [Note] WSREP: Member 0.0 (node) desyncs itself from group",
			expected: regexTestState{
				LogCtx: types.LogCtx{Desynced: true},
			},
			expectedOut: "node desyncs itself from group",
			key:         "RegexDesync",
		},

		{
			log: "2001-01-01  1:01:01 0 [Note] WSREP: Member 0.0 (node) resyncs itself to group",
			expected: regexTestState{
				LogCtx: types.LogCtx{Desynced: false},
			},
			input: regexTestState{
				LogCtx: types.LogCtx{Desynced: true},
			},
			expectedOut: "node resyncs itself to group",
			key:         "RegexResync",
		},

		{
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 1(node1) initiates vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,bdb2b9234ae75cb3:  some error, Error_code: 123;\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expectedOut: "inconsistency vote started by node1(seqno:20)",
			expected: regexTestState{
				LogCtx: types.LogCtx{Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			key: "RegexInconsistencyVoteInit",
		},
		{
			log: "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 1(node1) initiates vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,bdb2b9234ae75cb3:  some error, Error_code: 123;\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node1"}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expectedOut: "inconsistency vote started(seqno:20)",
			key:         "RegexInconsistencyVoteInit",
		},

		{
			log: "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 2(node2) responds to vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,0000000000000000: Success\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "0000000000000000", Error: "Success"}}}}},
			},
			expectedOut: "consistency vote(seqno:20): voted Success",
			key:         "RegexInconsistencyVoteRespond",
		},
		{
			log: "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 2(node2) responds to vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,bdb2b9234ae75cb3: some error\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expectedOut: "consistency vote(seqno:20): voted same error",
			key:         "RegexInconsistencyVoteRespond",
		},
		{
			// could not actually find a "responds to" with any error for now
			log: "{\"log\":\"2001-01-01T01:01:01.000000Z 0 [Note] [MY-000000] [Galera] Member 2(node2) responds to vote on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,ed9774a3cad44656: some different error\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "ed9774a3cad44656", Error: "some different error"}}}}},
			},
			expectedOut: "consistency vote(seqno:20): voted different error",
			key:         "RegexInconsistencyVoteRespond",
		},

		{
			log:         "{\"log\":\"2001-01-01T01:01:01.000000Z 1 [ERROR] [MY-000000] [Galera] Inconsistency detected: Inconsistent by consensus on 8c9b5610-e020-11ed-a5ea-e253cc5f629d:127\n\t at galera/src/replicator_smm.cpp:process_apply_error():1469\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			expectedOut: "found inconsistent by vote",
			key:         "RegexInconsistencyVoted",
		},

		{
			log: "Winner: bdb2b9234ae75cb3",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expectedOut: "consistency vote(seqno:20): won",
			key:         "RegexInconsistencyWinner",
		},
		{
			log: "Winner: 0000000000000000",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "0000000000000000", Error: "Success"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "0000000000000000", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "0000000000000000", Error: "Success"}}}}},
			},
			expectedOut: "consistency vote(seqno:20): lost",
			key:         "RegexInconsistencyWinner",
		},
		{
			name: "already voted conflict, should not print anything",
			log:  "Winner: 0000000000000000",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node1"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			displayerExpectedNil: true,
			key:                  "RegexInconsistencyWinner",
		},

		{
			log: "{\"log\":\"2001-01-01T01:01:01.000000Z 1 [ERROR] [MY-000000] [Galera] Recovering vote result from history: 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,bdb2b9234ae75cb3\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "bdb2b9234ae75cb3"}}}}},
			},
			expectedOut: "consistency vote(seqno:20): voted same error",
			key:         "RegexInconsistencyRecovery",
		},
		{
			log: "{\"log\":\"2001-01-01T01:01:01.000000Z 1 [ERROR] [MY-000000] [Galera] Recovering vote result from history: 8c9b5610-e020-11ed-a5ea-e253cc5f629d:20,0000000000000000\n\",\"file\":\"/var/lib/mysql/mysqld-error.log\"}",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{MD5: "0000000000000000"}}}}},
			},
			expectedOut: "consistency vote(seqno:20): voted Success",
			key:         "RegexInconsistencyRecovery",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 16 [ERROR] [MY-000000] [Galera] Vote 0 (success) on 7b1a6710-18da-11ed-b777-42b15728f657:20 is inconsistent with group. Leaving cluster.",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Winner: "bdb2b9234ae75cb3", Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "bdb2b9234ae75cb3", Error: "some error"}, "node2": types.ConflictVote{Error: "Success", MD5: "0000000000000000"}}}}},
			},
			expectedOut: "vote (success) inconsistent, leaving cluster",
			key:         "RegexInconsistencyVoteInconsistentWithGroup",
		},

		{
			log: "2001-01-01T01:01:01.000000Z 16 [ERROR] [MY-000000] [Galera] Recomputed vote based on error codes: 3638. New vote c4915064add984b1 will be used for further steps. Old Vote: b3be677140613e7",
			input: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "b3be677140613e7", Error: "some error"}, "node2": types.ConflictVote{MD5: "b3be677140613e7", Error: "some error"}}}}},
			},
			expected: regexTestState{
				LogCtx: types.LogCtx{OwnNames: []string{"node2"}, Conflicts: types.Conflicts{&types.Conflict{InitiatedBy: []string{"node1"}, Seqno: "20", VotePerNode: map[string]types.ConflictVote{"node1": types.ConflictVote{MD5: "c4915064add984b1", Error: "some error"}, "node2": types.ConflictVote{MD5: "c4915064add984b1", Error: "some error"}}}}},
			},
			expectedOut: "vote md5 recomputed from b3be677140613e7 to c4915064add984b1",
			key:         "RegexInconsistencyVoteRecomputed",
		},
	}

	iterateRegexTest(t, ApplicativeMap, tests)
}
