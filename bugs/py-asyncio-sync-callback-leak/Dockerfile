# 3.14.7 is the last release with the bug; the fix shipped in 3.14.8.
# asyncio is pure Python, so "after" patches the installed stdlib in place
# with the upstream commit.
FROM python:3.14.7-slim@sha256:51dafde81dbdb6ebde285137a295cf18a47ca95234fe388a343719cb97305b3d
RUN apt-get update && apt-get install -y --no-install-recommends patch && rm -rf /var/lib/apt/lists/*
ENV PATCH_DIR=/usr/local/lib/python3.14 PATCH_STRIP=2 \
    TEST_CMD="python -X dev -m unittest -v test_sync_callback_leak"
LABEL bughunts.expect="transport leaked"
COPY scripts/entry.sh /entry.sh
COPY bugs/py-asyncio-sync-callback-leak/ /bug/
WORKDIR /bug
ENTRYPOINT ["/entry.sh"]
