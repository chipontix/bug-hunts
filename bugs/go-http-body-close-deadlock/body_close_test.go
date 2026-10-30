package gohttp

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// A Read that is blocked on the response body when another goroutine calls
// Close must return once the body ends, and the connection must stay usable.
// On go1.27.1 the Read never returns.
func TestConcurrentBodyReadAndEarlyClose(t *testing.T) {
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/next" {
			return
		}
		// Chunked response: headers go out now, the body only after release.
		w.WriteHeader(http.StatusOK)
		w.(http.Flusher).Flush()
		<-release
		fmt.Fprint(w, "tail")
	}))
	defer srv.Close()
	client := srv.Client()

	resp, err := client.Get(srv.URL)
	if err != nil {
		t.Fatal(err)
	}

	readDone := make(chan error, 1)
	go func() {
		_, err := io.Copy(io.Discard, resp.Body)
		readDone <- err
	}()
	// Let the reader block inside Body.Read waiting for the first chunk.
	time.Sleep(100 * time.Millisecond)

	// Close before EOF hands the rest of the body to the transport, which
	// drains it for up to 50ms so the connection can be reused. Ending the
	// body inside that window is what lets the drain succeed.
	if err := resp.Body.Close(); err != nil {
		t.Fatalf("Body.Close = %v", err)
	}
	close(release)

	select {
	case <-readDone:
	case <-time.After(5 * time.Second):
		t.Fatal("DEADLOCK: Body.Read did not return within 5s after the body ended")
	}

	// The drained connection goes back to the pool and serves the next request.
	next, err := client.Get(srv.URL + "/next")
	if err != nil {
		t.Fatalf("follow-up request: %v", err)
	}
	next.Body.Close()
}
