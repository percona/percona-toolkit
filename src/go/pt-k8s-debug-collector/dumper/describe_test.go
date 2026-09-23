// This program is copyright 2020-2026 Percona LLC and/or its affiliates.
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

package dumper

import (
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/fake"
)

func TestDescribePodIncludesLastStateAndExitCode(t *testing.T) {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: "test-pod", Namespace: "test-ns"},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{Name: "app"}},
		},
		Status: corev1.PodStatus{
			ContainerStatuses: []corev1.ContainerStatus{{
				Name: "app",
				LastTerminationState: corev1.ContainerState{
					Terminated: &corev1.ContainerStateTerminated{
						Reason:   "Error",
						ExitCode: 1,
					},
				},
			}},
		},
	}

	client := fake.NewSimpleClientset(pod)

	out, err := describePod(client, "test-ns", "test-pod")
	if err != nil {
		t.Fatalf("describePod returned error: %v", err)
	}

	for _, want := range []string{"test-pod", "Last State", "Exit Code"} {
		if !strings.Contains(out, want) {
			t.Errorf("describe output missing %q\n---\n%s", want, out)
		}
	}
}
