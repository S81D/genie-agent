#!/usr/bin/env bash
#
# ar23_20n_ccar.sh — AR23_20n_00_000, CC nu_mu + nu_e_bar on 40Ar, 0.1-10 GeV,
# flux E^2 exp(-E). Same matrix as john_ccar_flux.sh, one tune. 2 samples,
# smoke 10k / prod 500k each.
#
#   bash grid/campaigns/ar23_20n_ccar.sh {stage | smoke [--dry-run] | prod [--dry-run] | status}
#
# Jobs tagged runtype  ccar-n / ccar-n-smoke  (separate from the ccar/* campaign).
# Spline: $SPLINE_SRC/AR23_20n_00_000/gxspl-NUbig.xml (prebuilt).
#
# NOTE: AR23_20n's own gmkspl produced a zero QEL xsec in earlier testing (the
# tune's NievesQELCCPXSec/ZExp config). The smoke MUST pass before prod — if
# gevgen loops "No interaction could be selected", the prebuilt spline is bad.
set -euo pipefail
export TUNES="AR23_20n_00_000"
export RUNTYPE="ccar-n"
exec "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/john_ccar_flux.sh" "$@"
