#!/usr/bin/env bash
# Builds every bug image, runs its regression test before and after the
# upstream fix, and prints a table. Raw output goes to results/<bug>/.
# A bug passes verification only if "before" fails with its expected marker
# (the bughunts.expect image label) in the output and "after" passes.
#   scripts/verify.sh                 all bugs
#   scripts/verify.sh go-flate-preset-dict py-asyncio-close-during-accept
set -uo pipefail
cd "$(dirname "$0")/.."

if [ $# -gt 0 ]; then
  bugs=("$@")
else
  bugs=()
  for d in bugs/*/; do bugs+=("$(basename "$d")"); done
fi

now() { python3 -c 'import time; print(time.time())'; }
secs() { python3 -c "print(f'{$2 - $1:.1f}')"; }

mkdir -p results
{
  echo "date: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "host: $(uname -sm)"
  docker info --format 'docker: {{.ServerVersion}}, {{.OperatingSystem}}, {{.Architecture}}, {{.NCPU}} CPUs, {{.MemTotal}} bytes RAM'
} > results/environment.txt
rows=()
bad=0
t0=$(now)
for bug in "${bugs[@]}"; do
  img="bughunts-$bug"
  out="results/$bug"
  mkdir -p "$out"
  echo "== $bug: build" >&2
  if ! docker build -q -t "$img" -f "bugs/$bug/Dockerfile" . >/dev/null; then
    rows+=("| $bug | BUILD ERROR | - | - | - |")
    bad=1
    continue
  fi
  expect=$(docker inspect -f '{{index .Config.Labels "bughunts.expect"}}' "$img")
  for mode in before after; do
    echo "== $bug: $mode" >&2
    start=$(now)
    docker run --rm --name "$img-$mode" "$img" "$mode" >"$out/$mode.log" 2>&1
    rc=$?
    elapsed=$(secs "$start" "$(now)")
    if [ "$mode" = before ]; then rc_before=$rc t_before=$elapsed; else rc_after=$rc t_after=$elapsed; fi
  done
  before="exit $rc_before"
  if [ "$rc_before" -eq 1 ] && grep -qF -- "$expect" "$out/before.log"; then
    before="FAIL"
  else
    bad=1
  fi
  after="exit $rc_after"
  if [ "$rc_after" -eq 0 ]; then after="PASS"; else bad=1; fi
  rows+=("| $bug | $before | $after | $t_before / $t_after | \`$expect\` |")
done

{
  echo "| bug | before fix | after fix | run time, s (before / after) | marker in failing output |"
  echo "|---|---|---|---|---|"
  printf '%s\n' "${rows[@]}"
} | tee results/summary.md

total=$(secs "$t0" "$(now)")
echo "total wall time: ${total}s" | tee -a results/environment.txt
[ "$bad" -eq 0 ] && echo "verify: OK" || echo "verify: UNEXPECTED RESULT (see results/)"
exit $bad
