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
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	log "github.com/sirupsen/logrus"
	logtest "github.com/sirupsen/logrus/hooks/test"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/fake"
	"k8s.io/client-go/rest"
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

func TestDescribePodRedactsPgbouncerSecretNames(t *testing.T) {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: "pgbouncer-pod", Namespace: "pgv2"},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{Name: "pgbouncer"}},
			Volumes: []corev1.Volume{
				{
					Name: "pgbouncer-config",
					VolumeSource: corev1.VolumeSource{Projected: &corev1.ProjectedVolumeSource{
						Sources: []corev1.VolumeProjection{
							{Secret: &corev1.SecretProjection{LocalObjectReference: corev1.LocalObjectReference{Name: "cluster1-pgbouncer"}}},
							{Secret: &corev1.SecretProjection{LocalObjectReference: corev1.LocalObjectReference{Name: "cluster1-cluster-cert"}}},
						},
					}},
				},
				{
					Name:         "pgbouncer-frontend",
					VolumeSource: corev1.VolumeSource{Secret: &corev1.SecretVolumeSource{SecretName: "cluster1-pgbouncer-frontend"}},
				},
			},
		},
	}

	client := fake.NewSimpleClientset(pod)

	out, err := describePod(client, "pgv2", "pgbouncer-pod")
	if err != nil {
		t.Fatalf("describePod returned error: %v", err)
	}

	for _, secret := range []string{"cluster1-pgbouncer", "cluster1-pgbouncer-frontend"} {
		if strings.Contains(out, secret) {
			t.Errorf("describe output contains pgbouncer secret name %q\n---\n%s", secret, out)
		}
	}
	if !strings.Contains(out, "cluster1-cluster-cert") {
		t.Errorf("describe output missing non-pgbouncer secret name\n---\n%s", out)
	}
	if strings.Count(out, "<redacted>") != 2 {
		t.Errorf("describe output should have 2 redacted secret names\n---\n%s", out)
	}
}

func TestDescribePodTimesOutOnHungAPIServer(t *testing.T) {
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-release
	}))
	t.Cleanup(srv.Close)
	t.Cleanup(func() { close(release) })

	client, err := kubernetes.NewForConfig(describeRestConfig(&rest.Config{Host: srv.URL}, 200*time.Millisecond))
	if err != nil {
		t.Fatal(err)
	}

	done := make(chan error, 1)
	go func() {
		_, err := describePod(client, "ns", "pod")
		done <- err
	}()

	select {
	case err := <-done:
		if err == nil {
			t.Fatal("describePod succeeded against a hung API server")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("describePod did not time out")
	}
}

func TestGetPodDescribeSkipsDeletedPod(t *testing.T) {
	hooks := log.StandardLogger().ReplaceHooks(make(log.LevelHooks))
	t.Cleanup(func() { log.StandardLogger().ReplaceHooks(hooks) })
	logHook := logtest.NewGlobal()

	d := &Dumper{describeClient: fake.NewSimpleClientset()}
	d.getPodDescribe(corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "gone", Namespace: "test-ns"}})

	for _, e := range logHook.AllEntries() {
		if e.Level <= log.ErrorLevel {
			t.Errorf("deleted pod logged at %s: %s", e.Level, e.Message)
		}
	}
	if e := logHook.LastEntry(); e == nil || e.Level != log.WarnLevel {
		t.Errorf("deleted pod should be logged as a warning, got %v", e)
	}
}
