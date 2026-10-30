# Go 1.27.1 is the last release with the bug; the fix shipped in 1.27.2.
# The stdlib source in GOROOT is what gets patched: `go test` rebuilds
# compress/flate from it, so "after" runs the exact upstream fix on 1.27.1.
FROM golang:1.27.1-bookworm@sha256:8d48e12ec56735e9358640898b9d9b9fcca110612ed8a5567438c0a1baa24e66
RUN apt-get update && apt-get install -y --no-install-recommends patch && rm -rf /var/lib/apt/lists/*
ENV GOTOOLCHAIN=local GOFLAGS=-count=1 \
    PATCH_DIR=/usr/local/go PATCH_STRIP=1 \
    BUILD_CMD="go vet ./..." \
    TEST_CMD="go test -v ./..."
LABEL bughunts.expect="dictionary leaked into output"
COPY scripts/entry.sh /entry.sh
COPY bugs/go-flate-preset-dict/ /bug/
WORKDIR /bug
# Warm the build cache so the timed runs measure the test, not the toolchain.
RUN go vet ./...
ENTRYPOINT ["/entry.sh"]
