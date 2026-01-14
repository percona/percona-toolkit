package dumper

import (
	"bytes"
	"sync"
)

// SafeLogger is a thread-safe io.Writer that accumulates log bytes.
type SafeLogger struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func NewSafeLogger() *SafeLogger { return &SafeLogger{} }

func (s *SafeLogger) Write(p []byte) (int, error) {
	s.mu.Lock()
	n, err := s.buf.Write(p)
	s.mu.Unlock()
	return n, err
}

func (s *SafeLogger) Bytes() []byte {
	s.mu.Lock()
	b := make([]byte, s.buf.Len())
	copy(b, s.buf.Bytes())
	s.mu.Unlock()
	return b
}

func (s *SafeLogger) String() string { return string(s.Bytes()) }

func (s *SafeLogger) DumpToArchive(archive *tarWriter, path string) error {
	if archive == nil {
		return nil
	}

	return archive.WriteFile(path, &s.buf, int64(s.buf.Len()))
}

func (s *SafeLogger) Reset() {
	s.mu.Lock()
	s.buf.Reset()
	s.mu.Unlock()
}
