#!/usr/bin/env bash
#
# merge_sample.sh — hadd a per-process grid sample into one gst.root + sanity check.
#
#   bash grid/local/merge_sample.sh <pnfs-sample-dir> [out.gst.root] [-g|-G] [-e EMIN -E EMAX]
#
#   <pnfs-sample-dir> = .../jobsub-lite/ccar/<tune>_<probe>   (holds 0000/ .. NNNN/)
#   -g   ALSO merge the per-process .ghep.root -> <dir(out)>/ghep/<base(out)>.ghep.root
#   -G   ONLY merge the .ghep.root (skip the gst merge + check — gst already done)
#
# Stages the per-process files to local scratch first (hadd straight off /pnfs
# NFS stalls on bulk reads), merges, cleans up, then runs check_sample.C on the
# gst. Override the stage location with STAGE_DIR= (ghep needs ~1 GB free).
set -euo pipefail

GBASE="${GENIEBASE:-/exp/dune/app/users/doran/grid/GENIE}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STAGE="${STAGE_DIR:-/tmp/merge.$$}"
EMIN=0.1 ; EMAX=10 ; DO_GHEP=0 ; DO_GST=1

SAMPLE_DIR=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) EMIN=$2; shift 2 ;;
    -E) EMAX=$2; shift 2 ;;
    -g) DO_GHEP=1; shift ;;
    -G) DO_GHEP=1; DO_GST=0; shift ;;
    *)  if [ -z "$SAMPLE_DIR" ]; then SAMPLE_DIR=$1; else OUT=$1; fi; shift ;;
  esac
done
[ -n "$SAMPLE_DIR" ] || { echo "usage: $0 <pnfs-sample-dir> [out.gst.root] [-g|-G] [-e EMIN -E EMAX]" >&2; exit 2; }
[ -d "$SAMPLE_DIR" ] || { echo "not a dir: $SAMPLE_DIR" >&2; exit 2; }
OUT="${OUT:-/tmp/$(basename "$SAMPLE_DIR")_merged.gst.root}"

command -v hadd >/dev/null 2>&1 || source "$GBASE/setup_env.sh"

mkdir -p "$STAGE"; trap 'rm -rf "$STAGE"' EXIT

_merge() {   # $1 = suffix (gst.root | ghep.root)   $2 = output path
  local sfx=$1 out=$2
  mapfile -t SRC < <(ls "$SAMPLE_DIR"/[0-9]*/*."$sfx" 2>/dev/null)
  [ "${#SRC[@]}" -gt 0 ] || { echo "no *.$sfx under $SAMPLE_DIR/*/" >&2; return 1; }
  echo ">>> $sfx : ${#SRC[@]} process files  ->  $out"
  local d; d="$STAGE/$sfx"; mkdir -p "$d"
  local i=0
  for f in "${SRC[@]}"; do cp "$f" "$d/$(printf '%04d' $i).$sfx"; i=$((i+1)); done
  mkdir -p "$(dirname "$out")"
  hadd -f "$out" "$d"/*."$sfx" >/dev/null
  rm -rf "$d"
  ls -lh "$out"
}

if [ "$DO_GST" = 1 ]; then
  _merge gst.root "$OUT"
  root -l -b -q "${HERE}/check_sample.C(\"${OUT}\", ${EMIN}, ${EMAX})"
fi

if [ "$DO_GHEP" = 1 ]; then
  base="$(basename "$OUT")"; base="${base%.gst.root}"
  _merge ghep.root "$(dirname "$OUT")/ghep/${base}.ghep.root"
fi
