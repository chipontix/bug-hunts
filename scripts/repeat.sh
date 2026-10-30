#!/usr/bin/env bash
# Runs one bug's test N times in each mode to check that the reproduction is
# stable. Writes results/<bug>/repeat.txt.   scripts/repeat.sh <bug> [N]
set -uo pipefail
cd "$(dirname "$0")/.."
bug=$1 n=${2:-20} img="bughunts-$1"
docker build -q -t "$img" -f "bugs/$bug/Dockerfile" . >/dev/null || exit 1
mkdir -p "results/$bug"
{
  echo "# scripts/repeat.sh $bug $n   ($(date -u +%Y-%m-%dT%H:%MZ))"
  for mode in before after; do
    codes=""
    for _ in $(seq "$n"); do
      docker run --rm "$img" "$mode" >/dev/null 2>&1
      codes="$codes $?"
    done
    fails=$(tr ' ' '\n' <<<"$codes" | grep -c '^1$')
    passes=$(tr ' ' '\n' <<<"$codes" | grep -c '^0$')
    echo "$mode: exit codes:$codes"
    echo "$mode: $fails/$n failed, $passes/$n passed"
  done
} | tee "results/$bug/repeat.txt"
