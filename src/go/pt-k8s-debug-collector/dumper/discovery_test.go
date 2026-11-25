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
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/discovery"
	"k8s.io/client-go/rest"
)

func discoveryServer(t *testing.T, unavailable string) *httptest.Server {
	t.Helper()
	responses := map[string]any{
		"/api": metav1.APIVersions{Versions: []string{"v1"}},
		"/api/v1": metav1.APIResourceList{
			GroupVersion: "v1",
			APIResources: []metav1.APIResource{{Name: "pods", Namespaced: true, Kind: "Pod"}},
		},
		"/apis": metav1.APIGroupList{Groups: []metav1.APIGroup{
			{
				Name:             "apps",
				Versions:         []metav1.GroupVersionForDiscovery{{GroupVersion: "apps/v1", Version: "v1"}},
				PreferredVersion: metav1.GroupVersionForDiscovery{GroupVersion: "apps/v1", Version: "v1"},
			},
			{
				Name:             "metrics.k8s.io",
				Versions:         []metav1.GroupVersionForDiscovery{{GroupVersion: "metrics.k8s.io/v1beta1", Version: "v1beta1"}},
				PreferredVersion: metav1.GroupVersionForDiscovery{GroupVersion: "metrics.k8s.io/v1beta1", Version: "v1beta1"},
			},
		}},
		"/apis/apps/v1": metav1.APIResourceList{
			GroupVersion: "apps/v1",
			APIResources: []metav1.APIResource{{Name: "deployments", Namespaced: true, Kind: "Deployment"}},
		},
		"/apis/metrics.k8s.io/v1beta1": metav1.APIResourceList{
			GroupVersion: "metrics.k8s.io/v1beta1",
			APIResources: []metav1.APIResource{{Name: "nodes", Kind: "NodeMetrics"}},
		},
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, ok := responses[r.URL.Path]
		if !ok || r.URL.Path == unavailable {
			http.Error(w, "service unavailable", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(body); err != nil {
			t.Error(err)
		}
	}))
	t.Cleanup(server.Close)
	return server
}

func TestDiscoverResources(t *testing.T) {
	tests := []struct {
		name        string
		unavailable string
		want        []schema.GroupVersionResource
		wantErr     bool
	}{
		{
			name: "all groups available",
			want: []schema.GroupVersionResource{
				{Version: "v1", Resource: "pods"},
				{Group: "apps", Version: "v1", Resource: "deployments"},
				{Group: "metrics.k8s.io", Version: "v1beta1", Resource: "nodes"},
			},
		},
		{
			name:        "one group unavailable",
			unavailable: "/apis/metrics.k8s.io/v1beta1",
			want: []schema.GroupVersionResource{
				{Version: "v1", Resource: "pods"},
				{Group: "apps", Version: "v1", Resource: "deployments"},
			},
		},
		{
			name:        "group list unavailable",
			unavailable: "/apis",
			wantErr:     true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := discoveryServer(t, tt.unavailable)
			d := &Dumper{discoveryClient: discovery.NewDiscoveryClientForConfigOrDie(&rest.Config{Host: server.URL})}

			resources, err := d.discoverResources()
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected an error, got none")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			got := slices.Concat(resources.NamespaceScoped, resources.ClusterScoped)
			if len(got) != len(tt.want) {
				t.Fatalf("resources = %v, want %v", got, tt.want)
			}
			for _, gvr := range tt.want {
				if !slices.Contains(got, gvr) {
					t.Errorf("resources = %v, want %v", got, tt.want)
				}
			}
		})
	}
}
