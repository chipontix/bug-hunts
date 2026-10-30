#!/bin/sh
# Container entrypoint shared by every bug image.
#   entry.sh before   run the regression test against the pinned upstream version
#   entry.sh after    apply /bug/fix.patch (the upstream fix) first, then run it
# Exit codes: 0 test passed, 1 test failed, 2 usage or patch error, 3 build error.
# The image sets PATCH_DIR, PATCH_STRIP, BUILD_CMD and TEST_CMD.
set -u
case "${1:-}" in
  before) ;;
  after)
    echo "+ patch -d $PATCH_DIR -p$PATCH_STRIP < fix.patch"
    patch -d "$PATCH_DIR" -p"$PATCH_STRIP" --forward --batch < /bug/fix.patch || exit 2
    ;;
  *) echo "usage: entry.sh before|after" >&2; exit 2 ;;
esac
cd /bug || exit 2
if [ -n "${BUILD_CMD:-}" ]; then
  echo "+ $BUILD_CMD"
  sh -c "$BUILD_CMD" || exit 3
fi
echo "+ $TEST_CMD"
sh -c "$TEST_CMD"
rc=$?
# Normalise: any test failure (assertion, sanitizer report, Go panic) is 1.
[ "$rc" -eq 0 ] || rc=1
echo "exit=$rc"
exit $rc
