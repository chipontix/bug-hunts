#!/usr/bin/env bash
# Prints the machine the results were measured on. Host lines that need macOS
# tools or colima are skipped where those are missing (e.g. on CI).
echo "date: $(date -u +%Y-%m-%dT%H:%MZ)"
echo "host: $(uname -sm)"
if command -v sysctl >/dev/null && sysctl -n machdep.cpu.brand_string >/dev/null 2>&1; then
  echo "host cpu: $(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.ncpu) cores, $(sysctl -n hw.memsize) bytes RAM"
fi
command -v sw_vers >/dev/null && echo "host os: macOS $(sw_vers -productVersion)"
if command -v colima >/dev/null; then
  echo "colima: $(colima version 2>/dev/null | head -1)"
  colima list 2>/dev/null | awk 'NR==1 || $2=="Running" {print "colima vm: " $0}'
fi
docker info --format 'docker: {{.ServerVersion}}, {{.OperatingSystem}}, kernel {{.KernelVersion}}, {{.Architecture}}, {{.NCPU}} CPUs, {{.MemTotal}} bytes RAM'
