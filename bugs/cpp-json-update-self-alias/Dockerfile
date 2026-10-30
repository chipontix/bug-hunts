# Pinned to the parent of the fix commit (develop, after v3.12.0; v3.12.0
# itself has the same bug). Header-only. ASan turns the reads of freed or
# relocated memory into a hard failure.
FROM gcc:15.3.0@sha256:dc99c5016a0fb74d4e9a392e7892966ec7f358af744799bd3479239598f79d45
ARG JSON_COMMIT=1d675cdb46973038f0087c24c0f399722e823281
RUN mkdir -p /src/json && curl -fsSL https://github.com/nlohmann/json/archive/${JSON_COMMIT}.tar.gz \
    | tar -xz --strip-components=1 -C /src/json
ENV PATCH_DIR=/src/json PATCH_STRIP=1 \
    ASAN_OPTIONS=detect_leaks=0 \
    BUILD_CMD="g++ -std=c++17 -g -O0 -fno-omit-frame-pointer -fsanitize=address,undefined -I/src/json/include self_alias_test.cc -o /tmp/t" \
    TEST_CMD="/tmp/t"
LABEL bughunts.expect="heap-use-after-free"
COPY scripts/entry.sh /entry.sh
COPY bugs/cpp-json-update-self-alias/ /bug/
WORKDIR /bug
ENTRYPOINT ["/entry.sh"]
