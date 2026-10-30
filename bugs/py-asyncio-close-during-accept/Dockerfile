# 3.14.10 is the newest 3.14 release and still has the bug; the fix is on the
# 3.14 branch but not released yet. asyncio is pure Python, so "after" patches
# the installed stdlib in place with the upstream commit.
FROM python:3.14.10-slim@sha256:3cabfd7d7aaf394e6040e79fa1eec6ca1c52b74ed9188650472695d9a9326999
RUN apt-get update && apt-get install -y --no-install-recommends patch && rm -rf /var/lib/apt/lists/*
ENV PATCH_DIR=/usr/local/lib/python3.14 PATCH_STRIP=2 \
    TEST_CMD="python -X dev -m unittest -v test_close_during_accept"
LABEL bughunts.expect="Error on transport creation for incoming connection: AssertionError"
COPY scripts/entry.sh /entry.sh
COPY bugs/py-asyncio-close-during-accept/ /bug/
WORKDIR /bug
ENTRYPOINT ["/entry.sh"]
