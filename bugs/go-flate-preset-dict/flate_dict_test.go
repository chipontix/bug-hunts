package goflate

import (
	"bytes"
	"compress/flate"
	"compress/zlib"
	"fmt"
	"io"
	"math/rand/v2"
	"testing"
)

// incompressible returns n pseudo-random bytes. Random data does not shrink,
// so the encoder falls back to a stored (or Huffman-only) block, which copies
// raw bytes out of its window: the path the bug is on.
func incompressible(n int) []byte {
	r := rand.New(rand.NewPCG(1, 2))
	b := make([]byte, n)
	for i := range b {
		b[i] = byte(r.Uint32())
	}
	return b
}

var dict = []byte("GET /api/v1/orders HTTP/1.1\r\nHost: ")

func TestFlateRoundTripWithPresetDict(t *testing.T) {
	for _, size := range []int{100, 763, 4096} {
		data := incompressible(size)
		for level := flate.HuffmanOnly; level <= flate.BestCompression; level++ {
			t.Run(fmt.Sprintf("size=%d/level=%d", size, level), func(t *testing.T) {
				var buf bytes.Buffer
				w, err := flate.NewWriterDict(&buf, level, dict)
				if err != nil {
					t.Fatal(err)
				}
				w.Write(data)
				if err := w.Close(); err != nil {
					t.Fatal(err)
				}
				got, err := io.ReadAll(flate.NewReaderDict(&buf, dict))
				if err != nil {
					t.Fatalf("decompress: %v", err)
				}
				if !bytes.Equal(got, data) {
					t.Errorf("got %d bytes, want %d; dictionary leaked into output: %v",
						len(got), len(data), bytes.HasPrefix(got, dict))
				}
			})
		}
	}
}

// zlib carries an Adler-32 of the uncompressed data, so the same bug shows up
// there as a checksum error instead of silently longer output.
func TestZlibRoundTripWithPresetDict(t *testing.T) {
	data := incompressible(763)
	var buf bytes.Buffer
	w, err := zlib.NewWriterLevelDict(&buf, zlib.BestCompression, dict)
	if err != nil {
		t.Fatal(err)
	}
	w.Write(data)
	w.Close()
	r, err := zlib.NewReaderDict(&buf, dict)
	if err != nil {
		t.Fatal(err)
	}
	got, err := io.ReadAll(r)
	if err != nil {
		t.Fatalf("decompress: %v (dictionary leaked into output)", err)
	}
	if !bytes.Equal(got, data) {
		t.Fatalf("got %d bytes, want %d", len(got), len(data))
	}
}
