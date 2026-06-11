package dumper

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"io"
	"os"
	"sync"
	"time"
)

// tarWriter is a thread-safe wrapper around tar.Writer
type tarWriter struct {
	mu  sync.Mutex
	tw  *tar.Writer
	gz  *gzip.Writer
	out *os.File
}

func NewTarWriter(filename string) (*tarWriter, error) {
	f, err := os.Create(filename)
	if err != nil {
		return nil, err
	}
	gz := gzip.NewWriter(f)

	return &tarWriter{
		tw:  tar.NewWriter(gz),
		gz:  gz,
		out: f,
	}, nil
}

func (s *tarWriter) Close() {
	s.tw.Close()
	s.gz.Close()
	s.out.Close()
}

func (t *tarWriter) WriteFile(path string, r io.Reader, size int64) error {
	t.mu.Lock()
	defer t.mu.Unlock()

	hdr := &tar.Header{
		Name:    path,
		Size:    size,
		Mode:    0644,
		ModTime: time.Now(),
	}

	if err := t.tw.WriteHeader(hdr); err != nil {
		return err
	}

	_, err := io.CopyN(t.tw, r, size)
	return err
}

func (t *tarWriter) WriteVirtualFile(path string, content []byte) error {
	return t.WriteFile(
		path,
		bytes.NewReader(content),
		int64(len(content)),
	)
}
