#!/usr/bin/env bash
#
# g18_10a_fe56.sh — G18_10a_02_11b, CC nu_mu + nu_e_bar on 56Fe, 5-50 GeV,
# "Deep-DIS-like" flux f(E) = (E/20)^2 exp(-E/20)  (peaks ~40 GeV — matches
# validation-plan Sample G: high-E DIS/charm sanity check).
#
#   bash grid/campaigns/g18_10a_fe56.sh {stage | smoke [--dry-run] | prod [--dry-run] | status}
#
# Reuses the SAME gxspl-NUbig.xml already staged for the Ar40 campaign — it
# covers Fe56 (1000260560) to 100 GeV, so `stage` just skips the spline copy
# (already present) and stages only the new flux table.
#
# Jobs tagged runtype  ccar-fe / ccar-fe-smoke  (separate from ccar/ccar-n).
# Output samples go in the SAME /exp/dune/data/.../G18_10a_02_11b/ dir as the
# Ar40 campaign — merge with distinct "Fe56" filenames, do not reuse the Ar40 names.
set -euo pipefail
export TUNES="G18_10a_02_11b"
export TARGET="1000260560"                          # 56Fe
export EMIN="5" ; export EMAX="50"
export FLUX_EXPR='(E/20)**2 * math.exp(-E/20)'
export FLUX_NAME="flux_DeepDIS_x20.data"             # distinct from flux_E2expE.data
export RUNTYPE="ccar-fe"
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/john_ccar_flux.sh" "$@"
