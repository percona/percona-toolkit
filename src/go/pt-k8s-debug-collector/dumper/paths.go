package dumper

import "path/filepath"

// /<location>/<namespace>/<podName>/summary.txt
func (d *Dumper) PodSummaryPath(namespace, podName string) string {
	return filepath.Join(d.location, namespace, podName, "summary.txt")
}

// /<location>/<namespace>/<podName>/<individualFile>
func (d *Dumper) PodIndividualFilesPath(namespace, podName, internalFilePath string) string {
	return filepath.Join(d.location, namespace, podName, internalFilePath)
}

// /<location>/<namespace>/secrets/<secret>.yaml
func (d *Dumper) PodSecretsPath(namespace, secretName string) string {
	return filepath.Join(d.location, namespace, "secrets", secretName+".yaml")
}

// /<location>/<namespace>/secrets/<secret>
func (d *Dumper) PodRawSecretsPath(namespace, secretName string) string {
	return filepath.Join(d.location, namespace, "secrets", secretName)
}

// /<location>/<logPrefix>.log
func (d *Dumper) DumperLogPath(logPrefix string) string {
	return filepath.Join(d.location, logPrefix+".txt")
}

// /<location>/<namespace>/<resourceName>.yaml
func (d *Dumper) PodResourcePath(namespace, resourceName string) string {
	if namespace == "" {
		namespace = "cluster-scope"
	}
	return filepath.Join(d.location, namespace, resourceName+".yaml")
}

// /<location>/<namespace>/<podName>/<containerName>.log
func (d *Dumper) PodLogPath(namespace, podName, containerName string) string {
	return filepath.Join(d.location, namespace, podName, containerName+".log")
}
