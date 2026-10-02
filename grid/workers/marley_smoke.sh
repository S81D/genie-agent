#!/bin/bash
#
# marley_smoke.sh — end-to-end check of the standalone MARLEY payload in ONE job:
#   marley version    (binary runs, libs resolve)
#     -> marley generate  (physics + the $MARLEY data search path)
#       -> marley summarize  (proves the ROOT interface actually linked)
#
# Proves the published MARLEY tarball works on a worker: the Spack gcc runtime
# is ahead of /usr/lib64 on LD_LIBRARY_PATH, $MARLEY resolves the .react /
# structure / optical_model data, both event writers work, and ifdh copies out.
# NOT a physics sample — small stats.
#
# Unlike the GENIE workers, this one WRITES ITS OWN CONFIG: `marley generate`
# takes a config file and nothing else, so the seed and event count (config
# keys, not flags) have to be templated in per process. The config template
# ships in the payload under configs/; -c also accepts an absolute path, so a
# file staged with `jobsub ... -f` in $CONDOR_DIR_INPUT can override it without
# republishing the tarball.
#
# Submit:
#   python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/marley_smoke.sh \
#       -N 1 --runtype marley --tar-label marley_v2_main \
#       --memory 2000MB --expected-lifetime 2h --disk 10GB --output-suffix .root \
#       -- -R @TAR_DIR@ -O @PNFS_OUT@ -c configs/ve40Ar_fd.js -n 200
#
# Conventions from worker_skeleton.sh (jobsub-lite monitor relies on them):
#   seed = CLUSTER*100000 + PROCESS ; outputs -> <PNFS>/<%04d>/ ; final line = DONE
set -e
date; hostname; uname -r

PAYLOAD_OVERRIDE=""; PNFS_OUTPUT_DIR=""
CONFIG="configs/ve40Ar_fd.js"; NEVENTS="200"
while getopts "R:O:c:n:" opt; do
  case $opt in
    R) PAYLOAD_OVERRIDE=$OPTARG ;;
    O) PNFS_OUTPUT_DIR=$OPTARG ;;
    c) CONFIG=$OPTARG ;;        # payload-relative, or an absolute path
    n) NEVENTS=$OPTARG ;;       # events to generate
    *) echo "bad flag: $opt" >&2; exit 2 ;;
  esac
done
[ -n "${PNFS_OUTPUT_DIR}" ] || { echo "-O <pnfs_output_dir> is required" >&2; exit 2; }

PROCESS_STR=$(printf "%04d" "${PROCESS:-0}")
# MARLEY's "seed" key takes a nonnegative 63-bit integer, so the ~1e12-1e13 this
# produces is safe — no int32 truncation to worry about here.
SEED=$((CLUSTER * 100000 + PROCESS))
echo "CLUSTER=${CLUSTER} PROCESS=${PROCESS} SEED=${SEED}"

# ── ifdh, then payload env ───────────────────────────────────────────────────
source /cvmfs/larsoft.opensciencegrid.org/setup-env.sh
spack load --first ifdhc

if [ -n "${PAYLOAD_OVERRIDE}" ]; then
  RCDS_DIR="${PAYLOAD_OVERRIDE%/}"
elif [ -n "${INPUT_TAR_FILE}" ]; then
  if [ -d "${INPUT_TAR_FILE}" ]; then RCDS_DIR="${INPUT_TAR_FILE%/}"
  else RCDS_DIR="$(dirname "${INPUT_TAR_FILE}")"; fi
else
  echo "no -R override and no INPUT_TAR_FILE — MARLEY payload unavailable" >&2; exit 3
fi
echo "RCDS_DIR=${RCDS_DIR}"
[ -f "${RCDS_DIR}/setup_marley_env.sh" ] \
  || { echo "no setup_marley_env.sh under ${RCDS_DIR}" >&2; exit 3; }

source "${RCDS_DIR}/setup_marley_env.sh" \
  || { echo "payload setup_marley_env.sh failed" >&2; exit 5; }
for b in marley ifdh; do
  command -v "$b" >/dev/null || { echo "$b not on PATH after env setup" >&2; exit 5; }
done

# ── Build this process's config ──────────────────────────────────────────────
case "${CONFIG}" in
  /*) CONFIG_PATH="${CONFIG}" ;;                  # e.g. a -f staged $CONDOR_DIR_INPUT file
  *)  CONFIG_PATH="${RCDS_DIR}/${CONFIG}" ;;
esac
[ -f "${CONFIG_PATH}" ] || { echo "config not found: ${CONFIG_PATH}" >&2; exit 2; }

STEM="marley_smoke_p${PROCESS_STR}_c${CLUSTER}"
JOB_CFG="${PWD}/job_config.js"
sed -e "s|@SEED@|${SEED}|g" \
    -e "s|@NEVENTS@|${NEVENTS}|g" \
    -e "s|@OUTSTEM@|${STEM}|g" \
    "${CONFIG_PATH}" > "${JOB_CFG}"

# A token this worker doesn't know would otherwise reach MARLEY as a syntax
# error hundreds of lines into the JSON — fail here with a clear message.
if grep -q '@[A-Z_]\{1,\}@' "${JOB_CFG}"; then
  echo "ERROR: unsubstituted token(s) left in ${JOB_CFG}:" >&2
  grep -n '@[A-Z_]\{1,\}@' "${JOB_CFG}" >&2
  exit 2
fi
echo "--- job_config.js (from ${CONFIG_PATH}) ---"
cat "${JOB_CFG}"
echo "--- end job_config.js ---"

HEPMC="${STEM}.hepmc3"
EVROOT="${STEM}.root"
SUMMARY="${STEM}.summary.root"

echo "=== [1/3] marley version ==="
marley version

echo "=== [2/3] marley generate  (${NEVENTS} events, seed ${SEED}) ==="
marley generate "${JOB_CFG}"

# -f is REQUIRED: without it, an existing output makes summarize prompt
# interactively (src/app/cmd_summarize.cc), which would hang a batch job.
echo "=== [3/3] marley summarize  (GHEP-equivalent -> flat ROOT TTree) ==="
marley summarize -f -o "${SUMMARY}" "${HEPMC}"

ls -alh

# ── Copy the artefacts to PNFS ───────────────────────────────────────────────
# job_config.js goes too, so the exact configuration that produced these events
# sits next to them on PNFS.
DEST="${PNFS_OUTPUT_DIR%/}/${PROCESS_STR}"
echo "ifdh mkdir_p ${DEST}"
ifdh mkdir_p "${DEST}"
N_COPIED=0
for f in "${EVROOT}" "${HEPMC}" "${SUMMARY}" "${JOB_CFG}"; do
  [ -e "$f" ] || { echo "MISSING expected output: $f" >&2; continue; }
  ifdh cp -D "$f" "${DEST}/"
  N_COPIED=$((N_COPIED + 1))
done
if [ "${N_COPIED}" -lt 3 ]; then
  echo "ERROR: expected 3 event outputs (root/hepmc3/summary), copied ${N_COPIED}" >&2
  exit 4
fi
echo "copied ${N_COPIED} file(s) to ${DEST}"

date
echo "DONE"
