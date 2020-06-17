package archive

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"io"
	"os"
	"path/filepath"
)

func Create(src string) error {
	var buf bytes.Buffer

	zr := gzip.NewWriter(&buf)
	tw := tar.NewWriter(zr)

	filepath.Walk(src, func(file string, fi os.FileInfo, err error) error {
		header, err := tar.FileInfoHeader(fi, file)
		if err != nil {
			return err
		}
		header.Name = filepath.ToSlash(file)

		err = tw.WriteHeader(header)
		if err != nil {
			return err
		}

		if !fi.IsDir() {
			data, err := os.Open(file)
			if err != nil {
				return err
			}
			if _, err := io.Copy(tw, data); err != nil {
				return err
			}
		}
		return nil
	})

	if err := tw.Close(); err != nil {
		return err
	}
	if err := zr.Close(); err != nil {
		return err
	}

	file, err := os.OpenFile("./cluster-dump.tar.gzip", os.O_CREATE|os.O_RDWR, os.FileMode(777))
	if err != nil {
		return err
	}
	if _, err := io.Copy(file, &buf); err != nil {
		return err
	}

	return nil
}
