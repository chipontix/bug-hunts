# Pinned to the parent of the fix commit; header-only, so the source tarball
# is all that is needed. ASan makes the one-byte over-read visible. -O0 on
# purpose: at -O1 the same test passed without a report in our runs (the byte
# read is only used when it != end, so the compiler may drop the load).
FROM gcc:15.3.0@sha256:dc99c5016a0fb74d4e9a392e7892966ec7f358af744799bd3479239598f79d45
ARG FMT_COMMIT=7071103ceadf5791d3edc47149969b42e8abc883
RUN mkdir -p /src/fmt && curl -fsSL https://github.com/fmtlib/fmt/archive/${FMT_COMMIT}.tar.gz \
    | tar -xz --strip-components=1 -C /src/fmt
ENV PATCH_DIR=/src/fmt PATCH_STRIP=1 \
    ASAN_OPTIONS=detect_leaks=0 \
    BUILD_CMD="g++ -std=c++20 -g -O0 -fno-omit-frame-pointer -fsanitize=address,undefined -DFMT_HEADER_ONLY -I/src/fmt/include error_code_test.cc -o /tmp/t" \
    TEST_CMD="/tmp/t"
LABEL bughunts.expect="heap-buffer-overflow"
COPY scripts/entry.sh /entry.sh
COPY bugs/cpp-fmt-error-code-oob/ /bug/
WORKDIR /bug
ENTRYPOINT ["/entry.sh"]
