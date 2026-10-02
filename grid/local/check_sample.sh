#!/usr/bin/env bash
#
# check_sample.sh — run check_sample.C on one or more GENIE gst.root files.
#
#   bash grid/local/check_sample.sh [-e EMIN] [-E EMAX] <file.gst.root> [more.gst.root ...]
#   bash grid/local/check_sample.sh /pnfs/.../ccar-smoke/AR23_20m_00_000_nuebar/0000/*.gst.root
#
# Sources $GENIEBASE/setup_env.sh for ROOT if `root` isn't already on PATH.
set -euo pipefail

EMIN=0.1 ; EMAX=10
GBASE="${GENIEBASE:-/exp/dune/app/users/doran/grid/GENIE}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MACRO="$HERE/check_sample.C"

while getopts "e:E:" opt; do
  case $opt in e) EMIN=$OPTARG ;; E) EMAX=$OPTARG ;; *) exit 2 ;; esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "usage: $0 [-e EMIN] [-E EMAX] <file.gst.root> ..." >&2; exit 2; }

command -v root >/dev/null 2>&1 || source "$GBASE/setup_env.sh"

for f in "$@"; do
  [ -f "$f" ] || { echo "skip (not found): $f" >&2; continue; }
  # copy /pnfs files to local scratch first — ROOT over NFS /pnfs can stall
  src="$f"
  case "$f" in
    /pnfs/*) src="/tmp/$(basename "$f")"; cp "$f" "$src" ;;
  esac
  root -l -b -q "${MACRO}(\"${src}\", ${EMIN}, ${EMAX})"
  [ "$src" = "$f" ] || rm -f "$src"
done
