# GENIE+INCL+MARLEY: 500k ν_μ on ⁴⁰Ar, MicroBooNE BNB flux (2026-08)

Production record written 2026-11-24 from the gpvm install, the sample files and the source repositories.
The raw evidence is in `~/hep/analyses/incl-marley-O16/bookkeeping/` (`ar500k_facts.txt`, `ar500k_facts_part2.txt`,
both collected on dunegpvm06 on 2026-11-24). An identical copy of this file is kept there.

## Summary

| | |
|---|---|
| Physics | GENIE with INCL++ cascade; MARLEY de-excites the INCL remnant (INCL's ABLA07 off) |
| Target, probe | ⁴⁰Ar (1000180400), ν_μ (14) |
| Flux | MicroBooNE MCC9 BNB, histogram `hEnumu_cv`, `-e 0,10` |
| Tune, generator list | `ARINCL23_20i_00_000`, `Default` = QEL/RES/DIS/MEC × CC/NC, all `-INCL` (no COH) |
| Events, seed | 500000, `-r 145000` |
| Made | 2026-08-21/22 on a DUNE gpvm (ghep 2026-08-22 00:02, gst 09:35 CDT) |

## Software (all checked on the gpvm unless marked)

| Component | Version | Where |
|---|---|---|
| GENIE | `S81D/Generator-DeExaaS` branch `incl-hepmc3-marley-SBND-ready` @ `f9b25c620eacb722b6c46a23ea0f23864dc89d2b`; tag **`genie-incl-marley-ar500k-2026-08`** | `/exp/dune/app/users/doran/GENIE_MARLEY/GENIE-INCL++-HEPMC3-MARLEY` (clean; one untracked `RECAP_OF_BUILD_CHANGES.txt`) |
| MARLEY | `S81D/marley` branch `GENIE-de-excite` @ `d5ef07f9cdc7d0ae96374305c924100fbb614ba0` (MARLEY 2.0.0 + "Patch marley-2.0.0 for GENIE+HepMC3+INCL compatibility"); tag **`genie-incl-marley-ar500k-2026-08`** | `/exp/dune/app/users/doran/GENIE_MARLEY/marley-2.0.0-GENIE-de-excite`. Cloned 2026-08-05, never moved (reflog); clean; `libMARLEY.so` built 2026-08-10 |
| INCL++ | Liang Liu's GENIE build; **version unknown** (not a git tree) | `/exp/dune/app/users/liangliu/GENIEINCLXX/GENIE_INCL/inclxx_genie/install` (libs built 2026-04-16) |
| HepMC3 | 3.3.0 | spack-fnal-v1.0.0 `hepmc3-3.3.0-ugtfln6…` |
| Other externals | boost 1.82.0, lhapdf 6.5.5, libxml2 2.13.5, log4cpp 1.1.3 | spack-fnal-v1.0.0 |

Notes:
- The MARLEY library code at `d5ef07f` is identical to the `GENIE-de-excite` head `f0add40`. Only `src/tests/sampling.cc`
  and `include/marley/tests/Histogram.hh` differ. `f0add40` is tagged `GENIE-de-excite-2.0.0`.
- The build was configured with `/exp/dune/app/users/doran/GENIE_MARLEY/do_configure.sh` and `setup_env.sh`. They sit
  outside git and are **not copied here yet**. Options seen in `Make.config`:
  - `GOPT_ENABLE_INCL=YES`, `GOPT_ENABLE_HEPMC3_INTERFACE=YES`, `GOPT_ENABLE_MARLEY=YES`;
  - `GOPT_WITH_MARLEY_INC/LIB` → the MARLEY tree above (`include`, `build/lib`).
- `RECAP_OF_BUILD_CHANGES.txt` on the gpvm lists the build fixes:
  - Items 1–2 are in `do_configure.sh` / `setup_env.sh`.
  - Items 3–5 are committed on the branch: `a7f1243d` (HepMC3 and MARLEY wiring), `621cc27e` (`NoDeEx` `param_set` typo),
    `bb5fec9f` (ARINCL23_20i MEC config).
  - Its last note, to switch `INCLCascadeIntranuke.cxx:153` to `NucleusGenINCL/NoDeEx` when running with MARLEY, is
    **not** applied. Under this tune it is not needed: `config/ARINCL23_20i/NucleusGenINCL.xml` sets the `Default`
    `param_set` to `inclxx-de-excitation OFF` (`27fa172b`).

## Inputs

| Input | Path | sha256 |
|---|---|---|
| Spline | `/exp/dune/app/users/doran/GENIE_MARLEY/RUNS/gxspl-numu-Ar40-ARINCL23_20i.xml` (copy beside the outputs) | `78626d9909408dc0f739dce499e1ee54f26d0c5abf997ca3dcc608ca986a536f` |
| Flux | `/exp/dune/data/users/liangliu/runarea/INCL/APR16/LL25_20/flux/MCC9_FluxHist_volTPCActive.root`, `hEnumu_cv` | `68a2a428030895387aaa0eafd7690dd9602ddd3626e20ee39cd282c04118b99c` |

The `gmkspl` command that made the spline was not recorded.

## Command (as supplied by the user)

```
gevgen -n 500000 -p 14 -t 1000180400 \
  -e 0,10 \
  -f /exp/dune/data/users/liangliu/runarea/INCL/APR16/LL25_20/flux/MCC9_FluxHist_volTPCActive.root,hEnumu_cv \
  -r 145000 \
  --cross-sections gxspl-numu-Ar40-ARINCL23_20i.xml \
  --tune ARINCL23_20i_00_000 \
  --event-generator-list Default \
  -o numu_flux_500k.ghep.root
```

The output was renamed afterwards. `gntpc -f gst` was then run; its exact command was not recorded.

## Outputs

Directory: `/exp/dune/data/users/doran/GENIE-MARLEY-samples/MicroBooNE_CC_NC_numu/`

| File | Size (B) | sha256 |
|---|---|---|
| `GENIE_INCL_MARLEY_numu_flux_500k.ghep.root` | 924927897 | `433504c432051719d384256b08ae82307c991132fa78d5b70ee8ce0c56f3c39e` |
| `GENIE_INCL_MARLEY_numu_flux_500k.gst.root` | 799350237 | `cb83f71ee727c2d5036b642cc89a731536266575c2c9b09fabbc24c7a37f6d94` |
| `GENIE_INCL_MARLEY_numu_flux_500k.tar.gz` | 912902314 | not hashed |
| `sample_details.txt` | 1085 | not hashed |

The local copy `~/hep/analyses/MARLEY_DEV/GENIE_MARLEY_samples/GENIE_INCL_MARLEY_numu_MicroBooNE_flux_500k.gst.root` has
the same sha256. Its provenance sidecar is `<file>.json`.

Contents, read back from the gst (`gst;27`; `gst;26` is ROOT's backup cycle):
- 500000 events: CC 364071, NC 135929; QEL 256160, RES 157727, DIS 32804, MEC 53309, COH 0.
- E_ν from 0.046 to 4.99 GeV, mean 1.153 GeV. Whether the flux histogram ends at 5 GeV was not checked.

## Known issues

1. **Spin-parity of every remnant is fixed.** In MARLEY's `NucleusDecayer::assign_residue_attributes()` (`d5ef07f`)
   the level-density weights are never filled. Every remnant is de-excited as 1/2⁺ (odd A) or 0⁺ (even A).
   - This affects all de-excitation products in this sample.
   - Fixed on `S81D/marley` `GENIE-de-excite-v2.1.0` (`0fe2b9e`, MARLEY v2.1.0 + the GENIE patch + fix).
   - On 100 GENIE+INCL ⁴⁰Ar remnants (2 GeV ν_μ), the fix raises the γ multiplicity per de-excitation by ×1.23 and
     the summed E_γ by ×1.17. Not evaluated on this sample.
   - Details: `~/hep/analyses/incl-marley-O16/results/marley_fixA_vs_nofix_Ar40/`.
2. **NC and CC QE use different nuclear ground states in ARINCL23_20i.**
   - QEL-CC-INCL uses `NucleusGenINCL`.
   - QEL-NC-INCL uses `LocalFGM/SpectralFunctionLikeWithCorrelation`, and runs `NucBindEnergyAggregator` after the
     INCL cascade. Whether that subtracts binding a second time is not checked.
   - See `~/hep/analyses/incl-marley-O16/notes/step0_interface_review.md`.
