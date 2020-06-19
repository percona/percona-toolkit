package archive

import (
	"archive/tar"
	"compress/gzip"
	"os"
)

func TarWrite(path string, data map[string][]byte) error {
	tarFile, err := os.Create(path + ".tar.gz")
	if err != nil {
		return err
	}
	defer tarFile.Close()
	zr := gzip.NewWriter(tarFile)
	tw := tar.NewWriter(zr)
	defer zr.Close()
	defer tw.Close()
	for name, content := range data {
		hdr := &tar.Header{
			Name: name,
			Mode: 0600,
			Size: int64(len(content)),
		}
		if err := tw.WriteHeader(hdr); err != nil {
			return err
		}
		if _, err := tw.Write(content); err != nil {
			return err
		}
	}
	return nil
}
