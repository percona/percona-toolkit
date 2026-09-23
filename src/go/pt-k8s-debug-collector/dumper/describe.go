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
	log "github.com/sirupsen/logrus"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/kubectl/pkg/describe"
)

func describePod(clientset kubernetes.Interface, namespace, name string) (string, error) {
	pd := &describe.PodDescriber{Interface: clientset}
	return pd.Describe(namespace, name, describe.DescriberSettings{ShowEvents: true})
}

func (d *Dumper) getPodDescribe(pod corev1.Pod) {
	out, err := describePod(d.clientSet, pod.Namespace, pod.Name)
	if err != nil {
		log.Errorf("error describing pod %s/%s: %v", pod.Namespace, pod.Name, err)
		return
	}
	if err := d.archive.WriteVirtualFile(d.PodDescribePath(pod.Namespace, pod.Name), []byte(out)); err != nil {
		log.Errorf("error writing describe for pod %s/%s: %v", pod.Namespace, pod.Name, err)
	}
}
