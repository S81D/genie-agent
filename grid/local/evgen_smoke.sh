#!/usr/bin/env bash
#
# evgen_smoke.sh — LOCAL event-generation check on a GPVM (no grid).
#
# Runs gevgen -> gntpc off an EXISTING spline and sanity-checks the GST tree.
# Decoupled from spline generation — use a coworker's / prebuilt spline so a
# slow or broken gmkspl doesn't block validating that event generation works.
#
#   bash grid/local/evgen_smoke.sh \
#     -x /exp/dune/data/users/liangliu/runarea/genie_xsec/rc-v380/G18_10a_02_11b/gxspl-Ar40-numu-numubar-k100-e10.xml \
#     -T G18_10a_02_11b -t 1000180400
#
# Args:
#   -x  spline xml (required)          -T  tune (required)
#   -t  target PDG (required)          -p  probe PDG        (default 14 = numu)
#   -e  mono beam energy GeV           (default 2.5)
#   -n  n events                       (default 200)
#   -L  event-generator-list           (default Default)
#   -o  output dir                     (default /tmp/evgen_smoke_<ts>)
#   -G  GENIEBASE (to source setup_env.sh if $GENIE unset)
#       (default /exp/dune/app/users/doran/grid/GENIE)
set -euo pipefail

SPLINE="" ; TUNE="" ; TARGET="" ; PROBE=14
ENERGY=2.5 ; NEVT=200 ; GENLIST=Default ; OUTDIR="" ; GBASE=/exp/dune/app/users/doran/grid/GENIE
while getopts "x:T:t:p:e:n:L:o:G:" opt; do
  case $opt in
    x) SPLINE=$OPTARG ;;  T) TUNE=$OPTARG ;;   t) TARGET=$OPTARG ;;
    p) PROBE=$OPTARG ;;   e) ENERGY=$OPTARG ;; n) NEVT=$OPTARG ;;
    L) GENLIST=$OPTARG ;; o) OUTDIR=$OPTARG ;; G) GBASE=$OPTARG ;;
    *) echo "bad flag" >&2; exit 2 ;;
  esac
done
[ -n "$SPLINE" ] && [ -n "$TUNE" ] && [ -n "$TARGET" ] || {
  echo "-x <spline.xml>, -T <tune>, -t <target PDG> are required" >&2; exit 2; }
[ -f "$SPLINE" ] || { echo "spline not found: $SPLINE" >&2; exit 2; }
OUTDIR=${OUTDIR:-/tmp/evgen_smoke_$(date +%Y%m%d-%H%M%S)}

# ── GENIE env ───────────────────────────────────────────────────────────────
if ! command -v gevgen >/dev/null 2>&1; then
  echo ">>> sourcing $GBASE/setup_env.sh"
  # shellcheck disable=SC1091
  source "$GBASE/setup_env.sh"
fi
for b in gevgen gntpc root; do
  command -v "$b" >/dev/null || { echo "$b not on PATH" >&2; exit 3; }
done

mkdir -p "$OUTDIR"; cd "$OUTDIR"
export XSECSPLINEDIR="$OUTDIR"     # writable; gevgen uses --cross-sections anyway
GHEP="$OUTDIR/evgen_smoke.ghep.root"
GST="$OUTDIR/evgen_smoke.gst.root"

echo "=================================================================="
echo " spline : $SPLINE"
echo " tune   : $TUNE      target: $TARGET   probe: $PROBE"
echo " beam   : ${ENERGY} GeV mono   n: $NEVT   genlist: $GENLIST"
echo " outdir : $OUTDIR"
echo "=================================================================="

echo ">>> [1/3] gevgen"
time gevgen -p "$PROBE" -t "$TARGET" -e "$ENERGY" -n "$NEVT" \
     --cross-sections "$SPLINE" --tune "$TUNE" \
     --event-generator-list "$GENLIST" --seed 12345 \
     -o "$GHEP"

echo ">>> [2/3] gntpc (GHEP -> GST)"
time gntpc -i "$GHEP" -f gst -o "$GST"

echo ">>> [3/3] GST sanity check"
root -l -b -q "$GST" <<EOF
{
  TTree *t = (TTree*) _file0->Get("gst");
  if (!t) { printf("\nSMOKE_RESULT: SUSPECT  (no 'gst' tree in the file)\n"); gApplication->Terminate(1); }
  Long64_t N   = t->GetEntries();
  Long64_t exp = ${NEVT};
  Long64_t cc  = t->GetEntries("cc==1");
  Long64_t nc  = t->GetEntries("nc==1");
  Long64_t nan = t->GetEntries("Ev!=Ev || El!=El || pl!=pl");
  Long64_t had = t->GetEntries("nf>0");
  printf("\n--- GST summary (%s) ---\n", "$TUNE");
  printf("entries          : %lld   (expected %lld)\n", N, exp);
  printf("CC / NC          : %lld / %lld   (sum %lld)\n", cc, nc, cc+nc);
  printf("QEL RES DIS MEC COH DFR : %lld %lld %lld %lld %lld %lld\n",
    t->GetEntries("qel==1"), t->GetEntries("res==1"), t->GetEntries("dis==1"),
    t->GetEntries("mec==1"), t->GetEntries("coh==1"), t->GetEntries("dfr==1"));
  printf("events w/ final hadron (nf>0)        : %lld\n", had);
  printf("events w/ final pi (nfpip+nfpim+nfpi0): %lld\n", t->GetEntries("(nfpip+nfpim+nfpi0)>0"));
  printf("NaN in Ev/El/pl                       : %lld\n", nan);
  t->Scan("Ev:cc:qel:res:dis:mec:nf:nfp:nfn:nfpip:nfpim:nfpi0", "", "", 12);
  bool ok = (N == exp) && (cc + nc == N) && (nan == 0) && (had > 0);
  printf("\nSMOKE_RESULT: %s\n", ok ? "OK" : "SUSPECT");
}
EOF

echo
echo "outputs in $OUTDIR :"
ls -lh "$OUTDIR"
