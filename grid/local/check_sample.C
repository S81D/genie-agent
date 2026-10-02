// check_sample.C — sanity report for a GENIE gst.root event sample.
//
//   root -l -b -q 'grid/local/check_sample.C("file.gst.root", 0.1, 10)'
//
// emin/emax = the flux window used at generation (for the Ev-range check).

void _ascii_hist(TTree* t, const char* var, const char* cut, double lo, double hi,
                 int nb = 40, int width = 60) {
  t->Draw(Form("%s>>__h(%d,%g,%g)", var, nb, lo, hi), cut, "goff");
  TH1* h = (TH1*) gDirectory->Get("__h");
  if (!h || h->GetEntries() == 0) { printf("  (empty)\n"); return; }
  double mx = h->GetMaximum();
  for (int i = 1; i <= nb; ++i) {
    int bar = mx > 0 ? (int)(width * h->GetBinContent(i) / mx) : 0;
    printf("  %6.2f | %.*s %.0f\n", h->GetBinLowEdge(i),
           bar, "############################################################################",
           h->GetBinContent(i));
  }
  printf("  mean=%.3f  rms=%.3f  peak-bin=%.2f  underflow=%.0f overflow=%.0f\n",
         h->GetMean(), h->GetRMS(), h->GetBinCenter(h->GetMaximumBin()),
         h->GetBinContent(0), h->GetBinContent(nb + 1));
  delete h;
}

void check_sample(const char* fn, double emin = 0.1, double emax = 10.0) {
  TFile f(fn);
  TTree* t = (TTree*) f.Get("gst");
  if (!t) { printf("NO 'gst' tree in %s\n", fn); return; }
  const Long64_t N = t->GetEntries();
  printf("\n================ %s ================\n", fn);
  printf("entries                : %lld\n", N);
  if (N == 0) return;

  // ---- current / probe / final lepton -------------------------------------
  Long64_t cc = t->GetEntries("cc"), nc = t->GetEntries("nc");
  printf("CC / NC                : %lld / %lld%s\n", cc, nc,
         (nc ? "   <-- expected 0 for -L CC" : ""));
  printf("neu  (probe) min/max   : %g / %g   (single value => one probe: 14=nu_mu, -12=nu_e_bar)\n",
         t->GetMinimum("neu"), t->GetMaximum("neu"));
  printf("fspl (f.s. lepton)     : %g / %g   (nu_mu CC -> 13 mu-,  nu_e_bar CC -> -11 e+)\n",
         t->GetMinimum("fspl"), t->GetMaximum("fspl"));

  // ---- process breakdown --------------------------------------------------
  Long64_t qel = t->GetEntries("qel"), res = t->GetEntries("res"),
           dis = t->GetEntries("dis"), mec = t->GetEntries("mec"),
           coh = t->GetEntries("coh"), dfr = t->GetEntries("dfr");
  Long64_t sum = qel + res + dis + mec + coh + dfr;
  printf("QEL RES DIS MEC COH DFR : %lld %lld %lld %lld %lld %lld   (sum %lld / %lld)\n",
         qel, res, dis, mec, coh, dfr, sum, N);
  printf("  fractions            : %.3f %.3f %.3f %.3f %.4f %.4f\n",
         1.*qel/N, 1.*res/N, 1.*dis/N, 1.*mec/N, 1.*coh/N, 1.*dfr/N);

  // ---- energy / flux window --------------------------------------------------
  double evlo = t->GetMinimum("Ev"), evhi = t->GetMaximum("Ev");
  printf("Ev range               : %.3f - %.3f GeV   (flux window %.2f - %.2f)\n",
         evlo, evhi, emin, emax);
  Long64_t oob = t->GetEntries(Form("Ev<%g-1e-3 || Ev>%g+1e-3", emin, emax));
  printf("Ev outside window      : %lld  %s\n", oob, oob ? "<-- BAD" : "ok");
  printf("Ev spectrum (= flux x sigma, so peak sits ABOVE the pure-flux peak):\n");
  _ascii_hist(t, "Ev", "", emin, emax);

  // ---- kinematics sanity ------------------------------------------------------
  printf("Q2   : %.4f - %.2f GeV^2      W : %.3f - %.2f GeV\n",
         t->GetMinimum("Q2"), t->GetMaximum("Q2"),
         t->GetMinimum("W"),  t->GetMaximum("W"));
  printf("x    : %.4f - %.4f            y : %.4f - %.4f\n",
         t->GetMinimum("x"), t->GetMaximum("x"),
         t->GetMinimum("y"), t->GetMaximum("y"));
  printf("El > Ev violations      : %lld\n", t->GetEntries("El > Ev + 1e-3"));
  Long64_t nan = t->GetEntries("Ev!=Ev||El!=El||Q2!=Q2||W!=W||x!=x||y!=y");
  printf("NaN (Ev/El/Q2/W/x/y)   : %lld  (%.3f%%; GENIE leaves x/W undefined for "
         "some non-DIS channels)\n", nan, 100.*nan/N);
  printf("y outside [0,1]        : %lld     x_DIS outside [0,1] : %lld\n",
         t->GetEntries("y<0 || y>1"), t->GetEntries("dis && (x<-1e-6 || x>1.0001)"));

  // ---- final state / FSI ----------------------------------------------------
  printf("nf>0                   : %lld  (%.1f%%)\n",
         t->GetEntries("nf>0"), 100.*t->GetEntries("nf>0")/N);
  printf("events w/ f.s. pi      : %lld  (%.1f%%)   [pi+ %lld  pi- %lld  pi0 %lld]\n",
         t->GetEntries("(nfpip+nfpim+nfpi0)>0"),
         100.*t->GetEntries("(nfpip+nfpim+nfpi0)>0")/N,
         t->GetEntries("nfpip>0"), t->GetEntries("nfpim>0"), t->GetEntries("nfpi0>0"));
  t->Draw("nf>>__nf(60,0,60)", "", "goff");
  printf("mean final-state mult  : %.2f\n", ((TH1*)gDirectory->Get("__nf"))->GetMean());

  t->Scan("Ev:qel:res:dis:mec:Q2:W:y:nf:nfp:nfn:nfpip:nfpim:nfpi0", "", "colsize=6", 15);

  bool ok = (nc == 0) && (sum == N) && (oob == 0)
         && (t->GetEntries("El > Ev + 1e-3") == 0)
         && (t->GetEntries("y<0 || y>1") == 0)
         && (nan < 0.005 * N)                       // <0.5% undefined kinematics tolerated
         && (t->GetEntries("nf>0") > 0.5 * N);
  printf("\nSAMPLE_CHECK: %s\n", ok ? "OK" : "REVIEW");
}
