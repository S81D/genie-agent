#!/usr/bin/env bash
#
# john_ccar_flux.sh — flux-driven gevgen campaign driver (jobsub-lite).
#
# Defaults: CC  nu_mu + nu_e_bar  on  40Ar,  0.1-10 GeV,  flux f(E)=E^2 exp(-E),
#           tunes G18_10a_02_11b + AR23_20m_00_000  -> 4 samples,
#           smoke 10k events / sample, production -N 20 x -n 25000 = 500k / sample.
#
# Every knob is an env override (see the `: "${VAR:=...}"` block); thin wrappers
# like ar23_20n_ccar.sh just set a few and exec this.
#
# Subcommands:
#   stage             flux table + splines -> /pnfs scratch
#   smoke [--dry-run] one -N 1 job per (tune,probe)
#   prod  [--dry-run] one -N $PROD_N job per (tune,probe); prompts
#   status            list this campaign's jobs
#
# Run on a dunegpvm from $GENIEBASE after `kinit` + `htgettoken`; system python3.
set -euo pipefail

# ── config (env-overridable) ───────────────────────────────────────────────
GBASE="${GENIEBASE:-/exp/dune/app/users/doran/grid/GENIE}"
SKILL="$GBASE/grid/jobsub-lite"
WORKER="$GBASE/grid/workers/gevgen_worker.sh"
: "${TARLABEL:=genie_v3_8_0_rcv380}"

read -ra TUNES  <<< "${TUNES:-G18_10a_02_11b AR23_20m_00_000}"
read -ra PROBES <<< "${PROBES:-14 -12}"          # 14=nu_mu  -12=nu_e_bar
: "${TARGET:=1000180400}"                        # 40Ar
: "${GENLIST:=CC}"
: "${EMIN:=0.1}" ; : "${EMAX:=10}"
: "${FLUX_EXPR:=E**2 * math.exp(-E)}"            # python expr in E (GeV); `math` in scope
: "${RUNTYPE:=ccar}"                             # jobs tagged $RUNTYPE / $RUNTYPE-smoke

: "${SPLINE_SRC:=/exp/dune/data/users/doran/John_GENIEv3.8_splines/splines}"
: "${SPLINE_NAME:=gxspl-NUbig.xml}"
: "${PNFS_BASE:=/pnfs/dune/scratch/users/${USER}/genie_splines/rc-v380}"
: "${FLUX_NAME:=flux_E2expE.data}"

: "${SMOKE_N:=1}"  ; : "${SMOKE_NEVT:=10000}" ; : "${SMOKE_LIFETIME:=2h}"
: "${PROD_N:=20}"  ; : "${PROD_NEVT:=25000}"  ; : "${PROD_LIFETIME:=4h}"

RT_SMOKE="${RUNTYPE}-smoke"

# ── paths ──────────────────────────────────────────────────────────────────
flux_pnfs()   { echo "$PNFS_BASE/$FLUX_NAME"; }
spline_pnfs() { echo "$PNFS_BASE/$1/$SPLINE_NAME"; }
plabel()      { [ "$1" = 14 ] && echo numu || echo nuebar; }

# ── stage ──────────────────────────────────────────────────────────────────
# dCache is write-once over NFS: an existing /pnfs file can't be cp'd over.
# _stage skips anything already present — `rm` it first to force a replace
# (safe here: flux table is deterministic from FLUX_EXPR/EMIN/EMAX, splines
# are immutable inputs).
_stage() {  # src dst
  local src=$1 dst=$2
  if [ -e "$dst" ]; then echo "    already staged (skip): $dst"; return 0; fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst" && echo "    -> $dst"
}

cmd_stage() {
  mkdir -p "$PNFS_BASE"
  echo ">>> flux table  [ f(E) = $FLUX_EXPR  over ${EMIN}-${EMAX} GeV ]"
  local tmp; tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN
  EMIN="$EMIN" EMAX="$EMAX" FLUX_EXPR="$FLUX_EXPR" python3 - "$tmp" <<'PY'
import os, sys, math
emin, emax = float(os.environ["EMIN"]), float(os.environ["EMAX"])
expr = os.environ["FLUX_EXPR"]
npts = 400
with open(sys.argv[1], "w") as fh:
    for i in range(npts):
        E = emin * (emax / emin) ** (i / (npts - 1))       # log-spaced
        fh.write(f"{E:.6f}  {eval(expr):.8e}\n")
PY
  _stage "$tmp" "$(flux_pnfs)"

  for t in "${TUNES[@]}"; do
    local src="$SPLINE_SRC/$t/$SPLINE_NAME"
    [ -f "$src" ] || { echo "MISSING spline: $src" >&2; exit 1; }
    echo ">>> spline: $t"
    _stage "$src" "$(spline_pnfs "$t")"
  done
  echo ">>> staged under $PNFS_BASE :"; ls -lhR "$PNFS_BASE" | sed 's/^/    /'
}

# ── submit ─────────────────────────────────────────────────────────────────
submit_one() {   # runtype  -N  -n  lifetime  tune  probe  dryflag
  local runtype=$1 nproc=$2 nevt=$3 life=$4 tune=$5 probe=$6 dry=${7:-}
  local spl; spl="$(spline_pnfs "$tune")"
  local flux; flux="$(flux_pnfs)"
  local stem="${tune}_$(plabel "$probe")"
  [ -f "$spl" ]  || { echo "spline not staged: $spl  (run '$0 stage')" >&2; exit 1; }
  echo ">>> $runtype  $stem   -N $nproc  -n $nevt  ($((nproc*nevt)) events)"
  # shellcheck disable=SC2086
  python3 "$SKILL/scripts/jobsub.py" submit --worker "$WORKER" \
    -N "$nproc" --runtype "$runtype" --stem "$stem" --tar-label "$TARLABEL" \
    -f "$spl" -f "$flux" \
    --memory 2500MB --expected-lifetime "$life" --disk 20GB --output-suffix .gst.root \
    $dry \
    -- -R @TAR_DIR@ -O @PNFS_OUT@ \
       -S "$(basename "$spl")" -F "file:$(basename "$flux")" \
       -p "$probe" -t "$TARGET" -T "$tune" -L "$GENLIST" \
       -e "${EMIN},${EMAX}" -n "$nevt"
}

_submit_all() {  # runtype  -N  -n  lifetime  dryflag
  for t in "${TUNES[@]}"; do
    for p in "${PROBES[@]}"; do submit_one "$1" "$2" "$3" "$4" "$t" "$p" "$5"; done
  done
}

cmd_smoke() { _submit_all "$RT_SMOKE" "$SMOKE_N" "$SMOKE_NEVT" "$SMOKE_LIFETIME" "${1:-}"; }

cmd_prod() {
  local dry=${1:-} nsamp=$(( ${#TUNES[@]} * ${#PROBES[@]} ))
  if [ -z "$dry" ]; then
    echo "PRODUCTION [$RUNTYPE]: $nsamp samples x -N ${PROD_N} = $((nsamp*PROD_N)) grid jobs,"
    echo "            $nsamp x $((PROD_N*PROD_NEVT)) = $((nsamp*PROD_N*PROD_NEVT)) events total."
    local a=""; read -r -p "proceed? [y/N] " a || true
    [ "$a" = y ] || { echo "aborted."; exit 0; }
  fi
  _submit_all "$RUNTYPE" "$PROD_N" "$PROD_NEVT" "$PROD_LIFETIME" "$dry"
}

cmd_status() {
  python3 "$SKILL/scripts/jobsub.py" list | grep -E "(^| )${RUNTYPE}(-smoke)?-" || echo "(no $RUNTYPE jobs yet)"
}

# ── dispatch ───────────────────────────────────────────────────────────────
sub="${1:-}"; shift || true
DRY=""
if [ "${1:-}" = "--dry-run" ]; then DRY="--dry-run"; fi
case "$sub" in
  stage)  cmd_stage ;;
  smoke)  cmd_smoke "$DRY" ;;
  prod)   cmd_prod  "$DRY" ;;
  status) cmd_status ;;
  *) echo "usage: $0 {stage | smoke [--dry-run] | prod [--dry-run] | status}" >&2; exit 2 ;;
esac
