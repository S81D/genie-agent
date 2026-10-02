// plot_charm.C — validation-plan Sample G check: charm hadron species fractions
// and charm event fraction vs neutrino energy.
//
//   gntpc -i <sample>.ghep.root -f rootracker -o <sample>.rootracker.root
//   root -l -b -q 'plot_charm.C("<sample>.rootracker.root","charm.png")'
//
// Reads the rootracker format rather than the gst, for two reasons: it carries
// StdHepStatus so charm hadrons can be found whatever status they hold (they are
// produced by the charm hadronizer and then decayed, so they are typically
// kIStDecayedState = 3, not final state), and it needs no GENIE libraries.
//
// Prints a species x status table first. Check that before trusting the
// fractions: if a species appears at more than one status, the same physical
// hadron may be being counted twice (e.g. a pre-transport copy and a clone).

void plot_charm(const char* rtfile, const char* out = "charm.png")
{
  TFile f(rtfile, "READ");
  if (f.IsZombie()) { printf("cannot open %s\n", rtfile); return; }
  TTree* rt = (TTree*)f.Get("gRooTracker");
  if (!rt) { printf("no gRooTracker tree in %s\n", rtfile); return; }

  const int kNP = 4000;
  int    N = 0;
  static int    pdg[kNP];
  static int    st [kNP];
  static double p4 [kNP][4];
  rt->SetBranchAddress("StdHepN",      &N);
  rt->SetBranchAddress("StdHepPdg",     pdg);
  rt->SetBranchAddress("StdHepStatus",  st);
  rt->SetBranchAddress("StdHepP4",      p4);

  // The four species the validation plan asks for, plus a catch-all.
  const int   nsp = 5;
  const int   code[nsp]  = { 421, 411, 431, 4122, 0 };
  const char* name[nsp]  = { "D^{0}", "D^{+}", "D_{s}^{+}", "#Lambda_{c}^{+}", "other c" };
  auto species = [&](int p)->int {
    const int a = TMath::Abs(p);
    for (int s = 0; s < nsp-1; ++s) if (a == code[s]) return s;
    // any other open-charm hadron: 4th digit of the meson/baryon code
    if ((a >= 400 && a < 500) || (a >= 4000 && a < 5000)) return nsp-1;
    return -1;
  };

  long count[nsp] = {0};
  std::map<int, std::map<int,long> > bystatus;      // species -> status -> n
  long nev = 0, ncharm_ev = 0;

  const int    nE = 15;
  const double Elo = 5., Ehi = 50.;
  TH1D* hall = new TH1D("hall", "", nE, Elo, Ehi);
  TH1D* hchm = new TH1D("hchm", "", nE, Elo, Ehi);
  hall->Sumw2(); hchm->Sumw2();

  const Long64_t n = rt->GetEntries();
  for (Long64_t i = 0; i < n; ++i) {
    rt->GetEntry(i);
    ++nev;
    const double Ev = p4[0][3];                     // probe is entry 0
    hall->Fill(Ev);
    bool has = false;
    for (int j = 0; j < N && j < kNP; ++j) {
      const int s = species(pdg[j]);
      if (s < 0) continue;
      ++count[s];
      bystatus[s][st[j]]++;
      has = true;
    }
    if (has) { ++ncharm_ev; hchm->Fill(Ev); }
  }

  long tot = 0; for (int s = 0; s < nsp; ++s) tot += count[s];
  printf("\n%lld events, %ld with a charm hadron (%.2f%%), %ld charm hadrons total\n",
         (long long)nev, ncharm_ev, 100.*ncharm_ev/nev, tot);
  printf("\nspecies x status (check for double counting before trusting fractions)\n");
  printf("%-12s %8s   status:count ...\n", "species", "total");
  for (int s = 0; s < nsp; ++s) {
    if (!count[s]) continue;
    printf("%-12s %8ld  ", name[s], count[s]);
    for (auto& kv : bystatus[s]) printf(" %d:%ld", kv.first, kv.second);
    printf("\n");
  }

  if (!tot) { printf("\nno charm hadrons found - nothing to plot\n"); return; }

  // ---- draw ----------------------------------------------------------------
  gStyle->SetOptStat(0);
  TCanvas* c = new TCanvas("c", "charm", 1300, 560);
  c->Divide(2, 1);

  c->cd(1); gPad->SetGrid(); gPad->SetLeftMargin(0.14); gPad->SetBottomMargin(0.16);
  TH1D* hsp = new TH1D("hsp", "", nsp, 0, nsp);
  for (int s = 0; s < nsp; ++s) {
    hsp->SetBinContent(s+1, 100.*count[s]/tot);
    // binomial error on a fraction
    const double p = (double)count[s]/tot;
    hsp->SetBinError(s+1, 100.*TMath::Sqrt(p*(1-p)/tot));
    hsp->GetXaxis()->SetBinLabel(s+1, name[s]);
  }
  hsp->SetFillColor(kAzure-9); hsp->SetLineColor(kAzure+2); hsp->SetLineWidth(2);
  hsp->SetTitle(";;fraction of charm hadrons (%)");
  hsp->GetXaxis()->SetLabelSize(0.075);
  hsp->GetYaxis()->SetTitleSize(0.047); hsp->GetYaxis()->SetLabelSize(0.045);
  hsp->GetYaxis()->SetTitleOffset(1.15);
  hsp->GetYaxis()->SetRangeUser(0., 1.35*hsp->GetMaximum());
  hsp->Draw("HIST E1");
  TLatex tv; tv.SetTextSize(0.040); tv.SetTextAlign(21);
  for (int s = 0; s < nsp; ++s)
    if (count[s]) tv.DrawLatex(s+0.5, hsp->GetBinContent(s+1)+hsp->GetBinError(s+1)+0.6,
                               Form("%ld", count[s]));

  c->cd(2); gPad->SetGrid(); gPad->SetLeftMargin(0.14); gPad->SetBottomMargin(0.16);
  TH1D* hfrac = (TH1D*)hchm->Clone("hfrac");
  hfrac->Divide(hchm, hall, 100., 1., "B");         // binomial errors
  hfrac->SetMarkerStyle(20); hfrac->SetMarkerSize(1.2);
  hfrac->SetLineColor(kRed+1); hfrac->SetMarkerColor(kRed+1); hfrac->SetLineWidth(2);
  hfrac->SetTitle(";E_{#nu} (GeV);events with a charm hadron (%)");
  hfrac->GetXaxis()->SetTitleSize(0.052); hfrac->GetXaxis()->SetLabelSize(0.048);
  hfrac->GetYaxis()->SetTitleSize(0.047); hfrac->GetYaxis()->SetLabelSize(0.045);
  hfrac->GetYaxis()->SetTitleOffset(1.15);
  hfrac->GetYaxis()->SetRangeUser(0., 1.5*hfrac->GetMaximum());
  hfrac->Draw("E1");

  c->SaveAs(out);
  printf("\nwrote %s\n", out);
}
