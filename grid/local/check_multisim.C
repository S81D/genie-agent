// check_multisim.C — cross-job report for a MARLEY strength_variation multisim sample.
//
//   root -l -b -q 'grid/local/check_multisim.C("/pnfs/dune/scratch/users/doran/marley_dar/40Ar/v2")'
//
// Reads <dir>/NNNN/*.summary.root (the flat "mst" trees from `marley summarize`,
// one per grid process) and checks that the jobs can be merged:
//   - every file has the same weight names and flux-averaged xsec
//   - weights move only for discrete events (proc 100), never continuum (101)
//   - every job carries the SAME universes: each (level, universe) weight must
//     be identical across files. Discrete events are keyed by Ex, one per level.
//   - no two jobs share a seed (their first events all differ)
// Then the universe spread of the flux-averaged cross section, using
//   sigma_k = sigma_CV * <w_k>   (mean over ALL events of universe k's weight),
// which holds because each level's cross section is linear in its B(GT)/B(F).

#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <string>
#include <vector>

// <dir>/NNNN/*.summary.root, in process order
std::vector<std::string> _summary_files(const std::string& dir) {
  std::vector<std::string> subdirs, files;
  void* dp = gSystem->OpenDirectory(dir.c_str());
  if (!dp) return files;
  while (const char* e = gSystem->GetDirEntry(dp)) {
    std::string s(e);
    if (s.size() == 4 && s.find_first_not_of("0123456789") == std::string::npos)
      subdirs.push_back(s);
  }
  gSystem->FreeDirectory(dp);
  std::sort(subdirs.begin(), subdirs.end());

  const std::string suffix = ".summary.root";
  for (const auto& sd : subdirs) {
    std::string p = dir + "/" + sd;
    void* d2 = gSystem->OpenDirectory(p.c_str());
    if (!d2) continue;
    while (const char* e = gSystem->GetDirEntry(d2)) {
      std::string s(e);
      if (s.size() > suffix.size()
          && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0)
        files.push_back(p + "/" + s);
    }
    gSystem->FreeDirectory(d2);
  }
  return files;
}

void check_multisim(const char* dir) {
  auto files = _summary_files(dir);
  if (files.empty()) { printf("no NNNN/*.summary.root under %s\n", dir); return; }

  // Universe table of the first file that shows each level: Ex [keV] -> weights
  std::map<long, std::vector<double>> ref_levels;
  std::vector<std::string> ref_names;
  double ref_xsec = -1.;
  bool names_same = true, xsec_same = true;
  long long n_tot = 0, n_cont_moved = 0, n_compared = 0, n_mismatch = 0;
  std::vector<double> sum_w;                       // per-universe sum of weights
  std::set<std::pair<double, double>> first_events;

  printf("%-48s %7s %7s %7s %4s %12s\n", "file", "entries", "proc100", "proc101", "nW",
         "xsec[1e-42]");
  for (const auto& fn : files) {
    TFile f(fn.c_str(), "READ");
    TTree* t = (TTree*) f.Get("mst");
    if (!t) { printf("%s: no mst tree\n", fn.c_str()); continue; }

    // std::vector<std::string> is not a TObject, so GetObject rather than Get
    std::vector<std::string>* names = nullptr;
    f.GetObject("MARLEY_other_weight_names", names);
    if (names) {
      if (ref_names.empty()) ref_names = *names;
      else if (*names != ref_names) names_same = false;
    }

    int proc; double Ex, xsec, Ev, El; std::vector<double>* ow = nullptr;
    t->SetBranchAddress("proc", &proc);
    t->SetBranchAddress("Ex", &Ex);
    t->SetBranchAddress("xsec", &xsec);
    t->SetBranchAddress("Ev", &Ev);
    t->SetBranchAddress("El", &El);
    t->SetBranchAddress("other_weights", &ow);

    std::map<long, std::vector<double>> levels;    // this file's universe table
    long long n100 = 0, n101 = 0;
    for (Long64_t j = 0; j < t->GetEntries(); ++j) {
      t->GetEntry(j);
      if (j == 0) {
        first_events.insert({Ev, El});
        if (ref_xsec < 0.) ref_xsec = xsec;
        else if (xsec != ref_xsec) xsec_same = false;
      }
      if (sum_w.empty()) sum_w.assign(ow->size(), 0.);
      for (size_t k = 0; k < ow->size(); ++k) sum_w[k] += (*ow)[k];

      if (proc == 101) {
        ++n101;
        for (double w : *ow) if (std::abs(w - 1.) > 1e-12) { ++n_cont_moved; break; }
      }
      else if (proc == 100) {
        ++n100;
        long ex_keV = std::lround(Ex * 1e3);
        if (!levels.count(ex_keV)) levels[ex_keV] = *ow;   // weights fixed per level
      }
    }
    n_tot += t->GetEntries();
    printf("%-48s %7lld %7lld %7lld %4zu %12.4f\n", gSystem->BaseName(fn.c_str()),
           t->GetEntries(), n100, n101, ow ? ow->size() : 0, xsec);

    // Compare this file's universes with the reference, exactly (same binary)
    for (const auto& lv : levels) {
      auto it = ref_levels.find(lv.first);
      if (it == ref_levels.end()) { ref_levels[lv.first] = lv.second; continue; }
      for (size_t k = 0; k < lv.second.size(); ++k) {
        ++n_compared;
        if (k >= it->second.size() || lv.second[k] != it->second[k]) ++n_mismatch;
      }
    }
  }

  printf("\nfiles %zu | total entries %lld\n", files.size(), n_tot);
  printf("weight names identical: %s (%zu: %s .. %s)\n", names_same ? "yes" : "NO",
         ref_names.size(), ref_names.empty() ? "?" : ref_names.front().c_str(),
         ref_names.empty() ? "?" : ref_names.back().c_str());
  printf("xsec identical: %s (%.4f x 1e-42 cm^2)\n", xsec_same ? "yes" : "NO", ref_xsec);
  printf("continuum events with moved weights: %lld (want 0)\n", n_cont_moved);
  printf("universes: %zu levels; %lld (level, universe) pairs compared across files, "
         "%lld mismatches (want 0)\n", ref_levels.size(), n_compared, n_mismatch);
  printf("distinct first events: %zu of %zu (want all distinct -> seeds differ)\n",
         first_events.size(), files.size());

  // sigma_k / sigma_CV = <w_k>; mean and sample (N-1) std across universes
  size_t K = sum_w.size();
  if (K > 1 && n_tot > 0) {
    double m = 0., s2 = 0.;
    for (double s : sum_w) m += s / n_tot;
    m /= K;
    for (double s : sum_w) s2 += std::pow(s / n_tot - m, 2);
    double sd = std::sqrt(s2 / (K - 1));
    printf("sigma_k/sigma_CV over %zu universes: mean %.5f, sample std %.5f "
           "(-> %.2f%% 1-sigma on the total xsec from discrete strengths)\n",
           K, m, sd, 100. * sd);
  }
}
