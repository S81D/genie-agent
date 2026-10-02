#!/bin/bash
#
# gmkspl_worker.sh — HTCondor worker for GENIE v3.8 spline generation (jobsub-lite).
#
# The GENIE install travels as an RCDS/CVMFS payload (built + published from
# $GENIEBASE, see README). It arrives unpacked and read-only at a
# /cvmfs/fifeuserN.opensciencegrid.org/sw/dune/<hash>/ directory, delivered
# either as the -R argument (a published --tar-label) or via $INPUT_TAR_FILE
# (a one-off --tar-file dropbox tarball).
#
# Submit (smoke test):
#   SKILL=genie-agent/.claude/skills/jobsub-lite
#   python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/gmkspl_worker.sh \
#       -N 1 --runtype gmkspl --tar-label genie_v3_8_0_rcv380 \
#       --memory 2000MB --expected-lifetime 4h --disk 10GB --output-suffix .xml \
#       -- -R @TAR_DIR@ -O @PNFS_OUT@ \
#          -p 14 -t 1000060120 -T AR23_20i_00_000 -L CCQE -e 10 -n 100
#
# Conventions kept from templates/worker_skeleton.sh (the jobsub-lite monitor
# depends on them):
#   seed  = CLUSTER*100000 + PROCESS   unique across submissions; GENIE --seed is 64-bit
#   out  -> <PNFS>/<%04d PROCESS>/     `pull` and completion-counting walk this
#   exit 4 on zero outputs; the final line on success is a bare  DONE
set -e
date; hostname; uname -r

PAYLOAD_OVERRIDE=""
PNFS_OUTPUT_DIR=""
PROBE=""; TARGET=""; TUNE=""; GENLIST=""; MAXE=""; NKNOTS=""
while getopts "R:O:p:t:T:L:e:n:" opt; do
  case $opt in
    R) PAYLOAD_OVERRIDE=$OPTARG ;;   # CVMFS payload dir (substituted for @TAR_DIR@)
    O) PNFS_OUTPUT_DIR=$OPTARG ;;    # PNFS output base (substituted for @PNFS_OUT@)
    p) PROBE=$OPTARG ;;             # neutrino PDG or comma list, e.g. 14  or  14,-14
    t) TARGET=$OPTARG ;;            # target PDG or comma list,   e.g. 1000060120
    T) TUNE=$OPTARG ;;              # e.g. AR23_20i_00_000
    L) GENLIST=$OPTARG ;;           # event-generator-list, e.g. CCQE
    e) MAXE=$OPTARG ;;              # max spline energy [GeV]  (optional)
    n) NKNOTS=$OPTARG ;;            # knots per spline         (optional)
    *) echo "bad flag: $opt" >&2; exit 2 ;;
  esac
done

[ -n "${PNFS_OUTPUT_DIR}" ] || { echo "-O <pnfs_output_dir> is required" >&2; exit 2; }
{ [ -n "${PROBE}" ] && [ -n "${TARGET}" ] && [ -n "${TUNE}" ] && [ -n "${GENLIST}" ]; } \
  || { echo "-p, -t, -T and -L are all required" >&2; exit 2; }

PROCESS_STR=$(printf "%04d" "${PROCESS:-0}")
SEED=$((CLUSTER * 100000 + PROCESS))
echo "CLUSTER=${CLUSTER} PROCESS=${PROCESS} SEED=${SEED}"

# ── ifdh (data transfer) — load BEFORE the payload env so GENIE's libs can't ──
# shadow ifdh's own runtime (references/worker-patterns.md).
source /cvmfs/larsoft.opensciencegrid.org/setup-env.sh
spack load --first ifdhc

# ── Locate the unpacked GENIE payload ───────────────────────────────────────
if [ -n "${PAYLOAD_OVERRIDE}" ]; then
  RCDS_DIR="${PAYLOAD_OVERRIDE%/}"
elif [ -n "${INPUT_TAR_FILE}" ]; then
  if [ -d "${INPUT_TAR_FILE}" ]; then
    RCDS_DIR="${INPUT_TAR_FILE%/}"
  else
    RCDS_DIR="$(dirname "${INPUT_TAR_FILE}")"
  fi
else
  echo "no -R override and no INPUT_TAR_FILE — GENIE payload unavailable" >&2
  exit 3
fi
echo "RCDS_DIR=${RCDS_DIR}"
[ -f "${RCDS_DIR}/setup_env.sh" ] || { echo "no setup_env.sh under ${RCDS_DIR}" >&2; exit 3; }

# ── GENIE environment: reuse the payload's own setup_env.sh ─────────────────
# GENIEBASE override repoints GENIE / XSECSPLINEDIR / LD_LIBRARY_PATH at the
# CVMFS dir (the /exp build prefix does not exist here). The Spack instance is
# whatever setup_env.sh resolves — same file, same CVMFS, so the worker picks
# the same one the build used. (Set SPACK_SETUP here to force a specific one.)
export GENIEBASE="${RCDS_DIR}"
source "${RCDS_DIR}/setup_env.sh" || { echo "payload setup_env.sh failed" >&2; exit 5; }

# gmkspl writes -o explicitly, but GENIE still stats XSECSPLINEDIR — point it at
# writable scratch (CVMFS is read-only).
export XSECSPLINEDIR="${PWD}/xsec"; mkdir -p "${XSECSPLINEDIR}"

command -v gmkspl >/dev/null || { echo "gmkspl not on PATH after env setup" >&2; exit 5; }
command -v ifdh   >/dev/null || { echo "ifdh not on PATH" >&2; exit 5; }
echo "GENIE=${GENIE}   gmkspl=$(command -v gmkspl)"

# ── Run gmkspl ─────────────────────────────────────────────────────────────
PROBE_LABEL=$(echo "${PROBE}"  | tr ',' '-')
TARGET_LABEL=$(echo "${TARGET}" | tr ',' '-')
OUT="spl_${PROBE_LABEL}_${TARGET_LABEL}_${TUNE}_${GENLIST}_p${PROCESS_STR}_c${CLUSTER}.xml"

OPTS=""
[ -n "${MAXE}" ]   && OPTS="${OPTS} -e ${MAXE}"
[ -n "${NKNOTS}" ] && OPTS="${OPTS} -n ${NKNOTS}"

echo "+ gmkspl -p ${PROBE} -t ${TARGET}${OPTS} --tune ${TUNE} \\"
echo "         --event-generator-list ${GENLIST} --seed ${SEED} -o ${OUT}"
# ${OPTS} intentionally unquoted so it word-splits into separate flags.
gmkspl -p "${PROBE}" -t "${TARGET}" ${OPTS} \
       --tune "${TUNE}" --event-generator-list "${GENLIST}" \
       --seed "${SEED}" -o "${OUT}"

ls -alh

# ── Copy outputs to PNFS ───────────────────────────────────────────────────
DEST="${PNFS_OUTPUT_DIR%/}/${PROCESS_STR}"
echo "ifdh mkdir_p ${DEST}"
ifdh mkdir_p "${DEST}"
N_COPIED=0
for f in *.xml; do
  [ -e "$f" ] || continue
  ifdh cp -D "$f" "${DEST}/"
  N_COPIED=$((N_COPIED + 1))
done
if [ "${N_COPIED}" -eq 0 ]; then
  echo "ERROR: gmkspl produced no .xml — nothing copied to ${DEST}" >&2
  exit 4
fi
echo "copied ${N_COPIED} file(s) to ${DEST}"

date
echo "DONE"
