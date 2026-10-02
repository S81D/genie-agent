#!/bin/bash
#
# gevgen_worker.sh — HTCondor worker for GENIE v3.8 event generation (jobsub-lite).
#
#   gevgen  ->  gntpc (GHEP -> GST)
#
# The cross-section spline is NOT generated here — it is shipped as a per-job
# input file (`jobsub_submit -f /pnfs/.../spline.xml`) and lands at
# $CONDOR_DIR_INPUT/<basename>. Stage the spline to YOUR /pnfs/dune/scratch
# first (the grid transfer host can't read /exp/dune/data).
#
# Each of -N processes generates -n events with a unique reproducible seed
# (CLUSTER*100000 + PROCESS); combine the per-process GHEP/GST files afterward.
#
# Submit (mono-energetic smoke):
#   python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/gevgen_worker.sh \
#       -N 1 --runtype gevgen --tar-label genie_v3_8_0_rcv380 -f "$SPL" \
#       --memory 2500MB --expected-lifetime 2h --disk 15GB --output-suffix .gst.root \
#       -- -R @TAR_DIR@ -O @PNFS_OUT@ -S "$(basename "$SPL")" \
#          -p 14 -t 1000180400 -T G18_10a_02_11b -L Default -e 2.5 -n 500
#
# Submit (spectrum): '-e a,b' needs '-F'. Forms:
#   -F POWERLAW:1                 gevgen's built-in E^-alpha
#   -F func:x*x*exp(-x)           a TF1 expression (NO spaces / shell metachars —
#                                 fragile through jobsub; prefer file: below)
#   -F file:myflux.data          a 2-column "E  flux" text table, staged with -f
#   -F hist:myflux.root,numu_h   a TH1 in a staged root file
# file:/hist: names resolve to $CONDOR_DIR_INPUT — stage them with `jobsub_submit
# -f` alongside the spline.
#
# Conventions from worker_skeleton.sh (jobsub-lite monitor relies on them):
#   seed = CLUSTER*100000 + PROCESS ; outputs -> <PNFS>/<%04d>/ ; final line = DONE
set -e
date; hostname; uname -r

PAYLOAD_OVERRIDE=""; PNFS_OUTPUT_DIR=""; SPLINE_BASENAME=""; FLUX=""
PROBE=""; TARGET=""; TUNE=""; GENLIST="Default"; ENERGY=""; NEVT=""
while getopts "R:O:S:F:p:t:T:L:e:n:" opt; do
  case $opt in
    R) PAYLOAD_OVERRIDE=$OPTARG ;;
    O) PNFS_OUTPUT_DIR=$OPTARG ;;
    S) SPLINE_BASENAME=$OPTARG ;;   # spline filename as it lands in $CONDOR_DIR_INPUT
    F) FLUX=$OPTARG ;;              # gevgen -f flux spec; required when -e is a range
    p) PROBE=$OPTARG ;;             # single probe PDG, e.g. 14
    t) TARGET=$OPTARG ;;            # target PDG, e.g. 1000180400 (40Ar)
    T) TUNE=$OPTARG ;;              # e.g. G18_10a_02_11b
    L) GENLIST=$OPTARG ;;           # event-generator-list (default Default)
    e) ENERGY=$OPTARG ;;            # "2.5" mono, or "0.5,10" spectrum (needs -F)
    n) NEVT=$OPTARG ;;              # events THIS process generates
    *) echo "bad flag: $opt" >&2; exit 2 ;;
  esac
done
[ -n "${PNFS_OUTPUT_DIR}" ] || { echo "-O <pnfs_output_dir> is required" >&2; exit 2; }
{ [ -n "${SPLINE_BASENAME}" ] && [ -n "${PROBE}" ] && [ -n "${TARGET}" ] \
  && [ -n "${TUNE}" ] && [ -n "${ENERGY}" ] && [ -n "${NEVT}" ]; } \
  || { echo "-S, -p, -t, -T, -e, -n are all required" >&2; exit 2; }
case "${ENERGY}" in
  *,*) [ -n "${FLUX}" ] || { echo "-e '${ENERGY}' is a range — needs -F <flux spec>" >&2; exit 2; } ;;
esac

PROCESS_STR=$(printf "%04d" "${PROCESS:-0}")
SEED=$((CLUSTER * 100000 + PROCESS))
echo "CLUSTER=${CLUSTER} PROCESS=${PROCESS} SEED=${SEED}"

# ── ifdh, then payload env ───────────────────────────────────────────────────
echo "[$(date +%T)] loading ifdh"
source /cvmfs/larsoft.opensciencegrid.org/setup-env.sh
spack load --first ifdhc

if [ -n "${PAYLOAD_OVERRIDE}" ]; then
  RCDS_DIR="${PAYLOAD_OVERRIDE%/}"
elif [ -n "${INPUT_TAR_FILE}" ]; then
  if [ -d "${INPUT_TAR_FILE}" ]; then RCDS_DIR="${INPUT_TAR_FILE%/}"
  else RCDS_DIR="$(dirname "${INPUT_TAR_FILE}")"; fi
else
  echo "no -R override and no INPUT_TAR_FILE — GENIE payload unavailable" >&2; exit 3
fi
echo "RCDS_DIR=${RCDS_DIR}"
[ -f "${RCDS_DIR}/setup_env.sh" ] || { echo "no setup_env.sh under ${RCDS_DIR}" >&2; exit 3; }

echo "[$(date +%T)] sourcing payload setup_env.sh"
export GENIEBASE="${RCDS_DIR}"
source "${RCDS_DIR}/setup_env.sh" || { echo "payload setup_env.sh failed" >&2; exit 5; }
export XSECSPLINEDIR="${PWD}/xsec"; mkdir -p "${XSECSPLINEDIR}"
for b in gevgen gntpc ifdh; do
  command -v "$b" >/dev/null || { echo "$b not on PATH after env setup" >&2; exit 5; }
done
echo "[$(date +%T)] env ready. GENIE=${GENIE}"

# ── Locate the shipped spline ───────────────────────────────────────────────
SPLINE="${CONDOR_DIR_INPUT}/${SPLINE_BASENAME}"
if [ ! -f "${SPLINE}" ]; then
  echo "spline not found at ${SPLINE}; CONDOR_DIR_INPUT contents:" >&2
  ls -la "${CONDOR_DIR_INPUT}" >&2 || true
  exit 4
fi
echo "SPLINE=${SPLINE}  ($(stat -c%s "${SPLINE}" 2>/dev/null || echo '?') bytes)"

STEM="gev_${TUNE}_${TARGET}_p${PROBE}_${GENLIST}_p${PROCESS_STR}_c${CLUSTER}"
GHEP="${STEM}.ghep.root"
GST="${STEM}.gst.root"

FLUX_OPT=()
case "${FLUX}" in
  "")            : ;;
  POWERLAW:*)    FLUX_OPT=(-f "${FLUX}") ;;                       # gevgen built-in E^-alpha
  func:*)        FLUX_OPT=(-f "${FLUX#func:}") ;;                 # TF1 expression, verbatim
  file:*)        _ff="${CONDOR_DIR_INPUT}/${FLUX#file:}"
                 [ -f "${_ff}" ] || { echo "flux file not staged: ${_ff}" >&2; exit 4; }
                 FLUX_OPT=(-f "${_ff}") ;;                        # 2-col "E flux" text table
  hist:*)        _h="${FLUX#hist:}"
                 _ff="${CONDOR_DIR_INPUT}/${_h%%,*}"
                 [ -f "${_ff}" ] || { echo "flux root file not staged: ${_ff}" >&2; exit 4; }
                 FLUX_OPT=(-f "${_ff},${_h#*,}") ;;               # TH1 in a staged root file
  *)             FLUX_OPT=(-f "${FLUX}") ;;                       # fallback: pass through
esac

t0=${SECONDS}
echo "=== [1/2] [$(date +%T)] gevgen  (-p ${PROBE} -t ${TARGET} -e ${ENERGY}${FLUX:+ -f ${FLUX}} -n ${NEVT} -L ${GENLIST}) ==="
gevgen -p "${PROBE}" -t "${TARGET}" -e "${ENERGY}" "${FLUX_OPT[@]}" -n "${NEVT}" \
       --cross-sections "${SPLINE}" --tune "${TUNE}" \
       --event-generator-list "${GENLIST}" --seed "${SEED}" -o "${GHEP}"
echo "=== [1/2] done in $((SECONDS - t0))s ==="

t0=${SECONDS}
echo "=== [2/2] [$(date +%T)] gntpc (GHEP -> GST) ==="
gntpc -i "${GHEP}" -f gst -o "${GST}"
echo "=== [2/2] done in $((SECONDS - t0))s ==="

ls -alh

# ── Copy outputs to PNFS ───────────────────────────────────────────────────
DEST="${PNFS_OUTPUT_DIR%/}/${PROCESS_STR}"
echo "ifdh mkdir_p ${DEST}"
ifdh mkdir_p "${DEST}"
N_COPIED=0
for f in "${GHEP}" "${GST}"; do
  [ -e "$f" ] || { echo "MISSING expected output: $f" >&2; continue; }
  ifdh cp -D "$f" "${DEST}/"
  N_COPIED=$((N_COPIED + 1))
done
# GENIE also drops a <stem>.ghep.status file — copy it if present (non-fatal)
for f in *.ghep.status; do [ -e "$f" ] && ifdh cp -D "$f" "${DEST}/" || true; done
if [ "${N_COPIED}" -lt 2 ]; then
  echo "ERROR: expected 2 outputs (ghep/gst), copied ${N_COPIED}" >&2
  exit 4
fi
echo "copied ${N_COPIED} file(s) to ${DEST}"

date
echo "DONE"
