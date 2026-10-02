# GENIE v3.8 grid production (jobsub-lite + RCDS)

Run a local Spack build of **GENIE v3.8 (`rc-v380`)** on the Fermigrid: ship the
build as an RCDS/CVMFS tarball, drive jobs with the self-contained `jobsub-lite`
skill. No container, no pixi. First jobs are `gmkspl` splines.

**Build config:** PYTHIA8 + LHAPDF6, no INCL/MARLEY/HepMC3/Reweight. rc-v380
defaults its DIS hadronizer to Pythia8 (`config/AGKY2019.xml`) — the AR23/AR25/
G18 tunes all inherit that — and its pythia6-only build path is broken (an
unguarded `Pythia8Decayer2023.cxx::PrintDecayChannelInfo`). So PYTHIA8, not
PYTHIA6 as the old MARLEY-fork scripts used.

## GPVM layout

Everything lives under **`GENIEBASE = /exp/dune/app/users/doran/grid/GENIE`**:

```
/exp/dune/app/users/doran/grid/GENIE/
├── Generator/            git clone -b rc-v380 https://github.com/GENIE-MC/Generator.git
├── data/                 XSECSPLINEDIR              (created by build_genie.sh)
├── setup_env.sh          copied from grid/build/    (also goes in the tarball)
├── do_configure.sh       copied from grid/build/
├── GENIE_COMMIT.txt      the exact rc-v380 SHA
├── build.log
├── .jobsub/              jobsub-lite state          (created by `jobsub.py init`)
└── grid/                 <- this tree (scp'd from the workstation)
    ├── build/{setup_env.sh, do_configure.sh, build_genie.sh}
    ├── workers/{gmkspl_worker.sh, gevgen_worker.sh, smoke_chain.sh}
    ├── local/{evgen_smoke.sh, check_sample.{C,sh}, merge_sample.sh}
    ├── campaigns/john_ccar_flux.sh   <- CC νμ+ν̄e / 40Ar / E²e⁻ᴱ flux driver (§7)
    ├── jobsub-lite/      <- copy of genie-agent/.claude/skills/jobsub-lite/
    └── README.md
```

Get the pieces onto the GPVM:

```sh
BASE=/exp/dune/app/users/doran/grid/GENIE
mkdir -p $BASE
scp -r grid                         dunegpvm:$BASE/          # this tree
scp -r genie-agent/.claude/skills/jobsub-lite  dunegpvm:$BASE/grid/   # the skill
```

Run everything below **from `$BASE`** on a **dunegpvm**. `jobsub_lite` + a valid
token are needed for every step except the local build and `tarball build`.

```sh
cd /exp/dune/app/users/doran/grid/GENIE
export GENIEBASE=$PWD
SKILL=grid/jobsub-lite
```

---

## 0. Auth (once per session)

```sh
kinit $USER@FNAL.GOV
htgettoken -a htvaultprod.fnal.gov -i dune          # bearer token
klist -s && echo "kerberos ok"
```

`jobsub.py` scrubs `PYTHONPATH` / `CONDA_*` / `PIXI_*` before every jobsub/ifdh
call, but still: run it with **system `python3`**, never through pixi/conda.

---

## 1. Build GENIE

`setup_env.sh` is pinned to `spack-fnal-v1.1.0` with `@version`-pinned deps:
`gcc@12.5.0` (the compiler `root` was built with — bare `gcc` grabs the AL9
system 11.5.0 and fails to link), `root@6.28.12`, `pythia8@8.313`,
`lhapdf@6.5.5`, `log4cpp@1.1.3`, `libxml2@2.9.13`, `gsl@2.8`. All confirmed
present. Nothing to choose — just build:

```sh
bash grid/build/build_genie.sh            # ~30-60 min; JOBS=1 if the build races
```

`build_genie.sh` clones `Generator/` if it isn't there yet (`git clone -b
rc-v380 https://github.com/GENIE-MC/Generator.git`), copies `setup_env.sh` +
`do_configure.sh` up to `$GENIEBASE`, records the SHA to `GENIE_COMMIT.txt`,
configures, `make`s, and checks the 5 binaries. Record the SHA in the campaign
log; to freeze a production campaign check that SHA out explicitly
(`cd $GENIEBASE/Generator && git checkout <sha>`) and rebuild.

Local smoke (no grid):

```sh
source $GENIEBASE/setup_env.sh
gmkspl -p 14 -t 1000060120 --tune AR23_20i_00_000 \
       --event-generator-list CCQE -e 5 -n 20 -o /tmp/t.xml
grep -c '<spline' /tmp/t.xml          # > 0
```

Build hiccups (env override, then re-run `build_genie.sh`):
- `GLIBCXX_3.4.30` undefined ref at link → wrong gcc. `setup_env.sh` hard-errors
  early if `GCC_PATH` is `/usr`; the fix is `SPACK_GCC_SPEC=gcc@<v>` where `<v>`
  comes from `spack find --format '{name}@{version} %{compiler}' root@6.28.12`.
- *"ROOT needs MathMore/GSL"* → `SPACK_ROOT_SPEC='root@6.28.12 +mathmore'`.
- GENIE won't compile against `pythia8@8.313` → `SPACK_PYTHIA8_SPEC=pythia8@8.317`.

---

## 2. Post-build env check

Right after the build, confirm every dep resolved to CVMFS (not a local
`$HOME`/`/exp` Spack) — an overlay prefix can't ride in the grid tarball:

```sh
source $GENIEBASE/setup_env.sh
spack find --loaded --format '{name}@{version}  {prefix}'
```

All prefixes should be under `/cvmfs/larsoft.opensciencegrid.org/spack-fnal-v1.1.0/`.
If one isn't, pin that `SPACK_*_SPEC` in `grid/build/setup_env.sh` to a CVMFS
build and rebuild. Record the `spack find --loaded` output + `GENIE_COMMIT.txt`
in the campaign log.

---

## 3. Tarball → publish → catalog

```sh
# ROOT in this Spack set is built -march=x86-64-v3 (AVX2), so pin the worker
# microarch floor or v2-only nodes SIGILL:
python3 $SKILL/scripts/jobsub.py init --group dune \
    --requirements '(TARGET.Microarch>="x86_64-v3")'   # writes .jobsub/config.json

python3 $SKILL/scripts/jobsub.py tarball build --build-dir "$GENIEBASE" \
    --include Generator setup_env.sh \
    --exclude-component src --exclude-component .git --exclude-component tmp \
    --exclude-suffix .o --exclude-suffix .d --exclude-suffix .a \
    --name-prefix genie_v3_8_0_rcv380
#  ~0.6-1 GB uncompressed. Keeps Generator/{bin,lib,config,data};
#  Generator/data is 388 MB (hadron_tensors/ — needed by MEC). src/ dropped.

python3 $SKILL/scripts/jobsub.py publish \
    --tarball .jobsub/tarballs/genie_v3_8_0_rcv380_*.tar \
    --label genie_v3_8_0_rcv380
#  runs ONE sentinel grid job to discover the CVMFS path — ~5-20 min.

python3 $SKILL/scripts/jobsub.py verify --label genie_v3_8_0_rcv380     # -> ok
python3 $SKILL/scripts/jobsub.py labels
```

Rebuilds are cache-keyed on the tree (path+mtime+size) — re-running `tarball
build` after `make` picks up changes; an unchanged tree is a no-op.

---

## 4. Smoke test — one job, full pipeline

`smoke_chain.sh` runs `gmkspl → gevgen → gntpc` in a single job — proves the
tarball's three binaries, the tune (FSI / nuclear model / de-excitation / form
factors), and `ifdh` all work. Small stats, `CCQE`-only by default, ~10–20 min.

```sh
python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/smoke_chain.sh \
    -N 1 --runtype smoke --tar-label genie_v3_8_0_rcv380 \
    --memory 2500MB --expected-lifetime 4h --disk 15GB --output-suffix .gst.root \
    -- -R @TAR_DIR@ -O @PNFS_OUT@ \
       -p 14,-12 -t 1000180400 -T AR23_20n_00_000 \
       -L CCQE -E 5 -K 20 -g 14 -G 2.5 -m 500
#  --dry-run first. 14=numu -12=nuebar, 1000180400=40Ar.
```

**Do not add MEC to `-L` here without timing it first.** `1000180400` (40Ar) has
no native SuSAv2 MEC hadron tensor (`data/evgen/hadron_tensors/crpa_susav2/` only
covers C12/O16) — `SuSAv2MECPXSec` falls back to a C12-tensor-scaling correction
that is dramatically slower per energy knot. A handful of knots took hours
locally. Measure it (§6) before it ever goes in a `-n`/`-e` budget.

`@TAR_DIR@` → published CVMFS dir; `@PNFS_OUT@` → default
`/pnfs/dune/scratch/users/$USER/jobsub-lite/smoke/<stem>`.

```sh
python3 $SKILL/scripts/jobsub.py status   <jobid>
python3 $SKILL/scripts/jobsub.py fetchlog <jobid>       # .out must end with DONE
python3 $SKILL/scripts/jobsub.py pull     <jobid>       # xsec.xml + .ghep.root + .gst.root
```

Success = `status` → `done`, three files pulled, the `.gst.root` opens in ROOT
with a non-empty `gst` tree. Debug a failure: `fetchlog`, read `.err` (the
worker brackets each of the 3 phases with `=== [n/3] ===`), reproduce that one
command locally with the same `--seed`.

Then the pure-`gmkspl` production worker (`gmkspl_worker.sh`) for the real
spline sets — see §6.

---

## 5. Scaling to production

- **Consent gate.** A large `-N` campaign costs shared grid resources — name the
  scale you're launching. A `-N 1` smoke is fine unprompted.
- **Seeds.** `CLUSTER*100000 + PROCESS` is unique across *submissions* too, so
  splines from separate `submit` calls merge without RNG overlap.
- **Sizing.** `--expected-lifetime` is per *process*. Measure one process
  (`/usr/bin/time -v`, MaxRSS) and add ~30 % for `--memory`. Prefer many
  processes × shorter jobs, each ≳15-30 min so payload caching amortizes.
  One process per (probe, target) or per genlist chunk is the usual grain.
- **RCDS GC ~30 d.** `verify` warns at 21/28 d;
  `publish --tarball <x.tar> --label genie_v3_8_0_rcv380 --overwrite`
  re-pushes the identical tree to the same hash.
- **Scratch dCache GC ~30 d.** Mirror keeper splines to persistent with the
  directory structure preserved (`scratch` → `persistent` path swap), sha256
  both sides. Pattern: `genie-agent/.claude/skills/genie-grid/SKILL.md` §
  "Preserving splines".
- **Merge.** `gspladd -f *.xml -o gxspl-<tune>-<eN>.xml`; record the merged
  sha256 and unique-key count.

---

## 6. Validation spline campaign

Splines the v3.8.0 release validation plan needs, one `gmkspl_worker.sh` job per
row (comprehensive `-L Default`). Energies/probes are the plan's; **the plan is
out of date — confirm each before submitting.** Add `-14`/`-12` probes where a
sample is used for reweighting.

| Sample | Tune | Target (`-t`) | `-e` | Probes (`-p`) | Notes |
|---|---|---|---|---|---|
| A | `G18_10a_02_11b` | `1000180400` 40Ar | 10 | `14,-14` | RW baseline |
| B | `AR23_20m_00_000` | `1000180400` 40Ar | 10 | `14,-14` | hA2025 |
| **C** | `AR23_20n_00_000` | `1000180400` 40Ar | **100** | **`14,-12`** | hN2025 + BY2021 — first target |
| D | `G24_12a` | `1000060120` 12C | 5 | `14,-14` | Martini QEL+MEC |
| D | `G24_12a` | `1000180400` 40Ar | 5 | `14,-14` | |
| E | `AR25_20i_00_000` | `1000060120` 12C | 3 | `14,-14` | UnifiedQEL + zexp FF |
| E | `AR25_20i_00_000` | `1000180400` 40Ar | 3 | `14,-14` | |
| F | `GDM18_00a_00_000` | `1000180400` 40Ar | — | — | **needs a rebuild with `--enable-boosted-dark-matter`; not in this tarball** |
| G | `G18_10a_02_11b` | `1000260560` 56Fe | 50 | `14` | Pythia8 charm |

```sh
python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/gmkspl_worker.sh \
    -N 1 --runtype gmkspl --tar-label genie_v3_8_0_rcv380 \
    --memory 3000MB --expected-lifetime 8h --disk 15GB --output-suffix .xml \
    -- -R @TAR_DIR@ -O @PNFS_OUT@ \
       -p 14,-12 -t 1000180400 -T AR23_20n_00_000 -L Default -e 100 -n 200
```

`-L Default` on Ar40 to 100 GeV for two probes is DIS/charm-dominated — could be
2–6 h. If it overruns `--expected-lifetime`, split per probe (two `submit` calls,
`-p 14` and `-p -12`) or per genlist (`-L CCDIS`, `-L Charm`, … then `gspladd`).
Pull with `--suffix .xml`; merge a tune's shards with `gspladd`.

**MEC on `-L Default` — measure before submitting.** `1000180400` (40Ar) has no
native SuSAv2 MEC hadron tensor; `SuSAv2MECPXSec` falls back to a C12-tensor
scaling correction that is much slower per knot than a native lookup (a few
knots took *hours* in local testing — see §4). Before running `-L Default -n 200`
on Ar40:
1. Time one MEC knot in the background (§4's `nohup ... time gmkspl -L CCMEC -n 1`).
2. If the per-knot cost makes `-n 200` infeasible in one job, split `Default`
   into a fast shard (`-L CCinclMECnoDIS`-style, excluding MEC-CC/MEC-NC — or
   just QEL/RES/DIS/Charm individually) and a separate MEC shard with a
   reduced `-n` and a walltime sized to the measured cost; `gspladd` the shards.
3. C12 and O16 (Sample D/E targets) *do* have native tensors — this cost is
   Ar40-specific; don't assume Sample D/E MEC splines are equally slow.

---

## 7. Event generation

### Local check first (`grid/local/evgen_smoke.sh`)

`gevgen → gntpc` off an **existing** spline (a coworker's, or `/exp/dune/data/...`),
with a GST sanity check. Decoupled from spline generation.

```sh
bash grid/local/evgen_smoke.sh \
  -x /exp/dune/data/users/liangliu/runarea/genie_xsec/rc-v380/G18_10a_02_11b/gxspl-Ar40-numu-numubar-k100-e10.xml \
  -T G18_10a_02_11b -t 1000180400
```
Prints `SMOKE_RESULT: OK` when entries == N, CC+NC == N, no NaN, FSI fired
(`nf>0`). Use a **stable** tune's spline — `G18_10a_02_11b` or `AR23_20m_00_000`,
not `AR23_20n` (see §8).

### Grid (`grid/workers/gevgen_worker.sh`)

Same `gevgen → gntpc`, `-N` processes each doing `-n` events with a unique seed.
The spline ships as a per-job input (`-f`), so **stage it to your own /pnfs
scratch first** — the grid transfer host can't read `/exp/dune/data`:

```sh
SRC=/exp/dune/data/users/liangliu/runarea/genie_xsec/rc-v380/G18_10a_02_11b/gxspl-Ar40-numu-numubar-k100-e10.xml
DST=/pnfs/dune/scratch/users/$USER/genie_splines/rc-v380/G18_10a_02_11b/$(basename "$SRC")
mkdir -p "$(dirname "$DST")" && cp "$SRC" "$DST"     # both are NFS on the GPVM
#  ifdh not on your PATH? it isn't — setup_env.sh doesn't load it. For a small
#  XML `cp` is fine; if /pnfs NFS hangs, use ifdh from a FRESH shell:
#    source /cvmfs/larsoft.opensciencegrid.org/setup-env.sh && spack load --first ifdhc

# smoke (mono-energetic, 1 process) — proven working:
python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/gevgen_worker.sh \
    -N 1 --runtype gevgen --tar-label genie_v3_8_0_rcv380 -f "$DST" \
    --memory 2500MB --expected-lifetime 2h --disk 15GB --output-suffix .gst.root \
    -- -R @TAR_DIR@ -O @PNFS_OUT@ -S "$(basename "$DST")" \
       -p 14 -t 1000180400 -T G18_10a_02_11b -L Default -e 2.5 -n 500

# production — 500k events, flat-in-log spectrum (E^-1) over 0.5-10 GeV:
python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/gevgen_worker.sh \
    -N 20 --runtype gevgen --tar-label genie_v3_8_0_rcv380 -f "$DST" \
    --memory 2500MB --expected-lifetime 8h --disk 20GB --output-suffix .gst.root \
    -- -R @TAR_DIR@ -O @PNFS_OUT@ -S "$(basename "$DST")" \
       -p 14 -t 1000180400 -T G18_10a_02_11b -L Default -e 0.5,10 -F POWERLAW:1 -n 25000
#  -N 20 × -n 25000 = 500k. -e RANGE needs -F (POWERLAW:α | func:<expr> |
#  file:<staged 2-col E-flux table> | hist:<staged.root>,<hist>).
```

Pull `.ghep.root` + `.gst.root` per process; `hadd` the GSTs (or chain the
GHEPs) for analysis. Seeds are `CLUSTER*100000+PROCESS` — unique across the
campaign, so re-submissions to top up statistics don't collide.

### Campaign driver (`grid/campaigns/john_ccar_flux.sh`)

Wraps the above for a fixed matrix — **CC νμ + ν̄e on 40Ar, 0.1–10 GeV,
`E²e⁻ᴱ` flux, tunes `G18_10a_02_11b` + `AR23_20m_00_000`** (2 tunes × 2 probes
= 4 samples). Splines from `/exp/dune/data/users/doran/John_GENIEv3.8_splines/`.

```sh
cd /exp/dune/app/users/doran/grid/GENIE
kinit && htgettoken -a htvaultprod.fnal.gov -i dune

bash grid/campaigns/john_ccar_flux.sh stage          # flux table + splines -> /pnfs
bash grid/campaigns/john_ccar_flux.sh smoke          # 4 × (-N 1, -n 10000)
#   ... check the 4 smoke jobs: status, fetchlog for the [1/2] done-in-Ns time ...
bash grid/campaigns/john_ccar_flux.sh prod           # 4 × (-N 20, -n 25000 = 500k); prompts
bash grid/campaigns/john_ccar_flux.sh status
```

`--dry-run` after `smoke`/`prod` prints the `jobsub_submit` argv without submitting.
Outputs land under `/pnfs/dune/scratch/users/doran/jobsub-lite/${RUNTYPE}{,-smoke}/<tune>_<probe>/<%04d>/`.

Every knob is an env override (`TUNES` `PROBES` `RUNTYPE` `EMIN/EMAX` `FLUX_EXPR`
`SPLINE_NAME` `PROD_N/PROD_NEVT` …). Per-campaign wrappers set a few and `exec`
it — e.g. `grid/campaigns/ar23_20n_ccar.sh` = `TUNES=AR23_20n_00_000
RUNTYPE=ccar-n`. `status` filters to that campaign's `RUNTYPE`.

Merge + validate each finished sample (stages off /pnfs, `hadd`, `check_sample`;
`-g` also merges the `.ghep.root` into a `ghep/` subdir; `STAGE_DIR=` for the
staging scratch — ghep needs ~1 GB):
```sh
STAGE_DIR=/exp/dune/data/users/doran/.tmp bash grid/local/merge_sample.sh \
  /pnfs/dune/scratch/users/doran/jobsub-lite/ccar/AR23_20m_00_000_nuebar \
  /exp/dune/data/users/doran/GENIE-v3.8-test-production/AR23_20m_00_000/gev_...500k.gst.root \
  -g -e 0.1 -E 10
```
dCache scratch GC is ~30 days — deposit the merged files to `/exp/dune/data` or
`/pnfs/.../persistent`; keep the raw per-process dirs too if you may re-process.

**`partial` label with all outputs present** = a jobsub-lite completion-count
race (one worker log lagged at queue-drain; `partial` is terminal so it sticks).
Verify with `ls <sample>/[0-9]*/*.gst.root | wc -l`; fix the label by running
`jobsub.py pull <jobid>` from a shell with `ifdh` loaded, or ignore it.

---

## 8. Known follow-ups

- **`AR23_20n_00_000` is broken.** `gmkspl -L CCQE` on Ar40 runs for *hours* and
  produces a zero cross section (gevgen then infinite-loops "No interaction
  could be selected"). It's a "temporary" testing tune being force-pushed
  repeatedly; the `NievesQELCCPXSec/ZExp` axial-FF config is the likely culprit.
  Report upstream; use `AR23_20m_00_000` (its stable hA2025 sibling) meanwhile.
- **Nieves+RPA CCQE splines are slow in general.** `src/contrib/ccqe_spline_smoothing/`
  (`construct_representative_spline.py`, `replace_splines.py`) is the SBN/DUNE
  workflow for this — plain `gmkspl -L CCQE` per-nucleus doesn't scale. It's a
  validation-plan infra item. For event generation, use prebuilt splines.
- **DIS genlists** (`CCDIS`/`NCDIS`, or a full-tune genlist): two runtime data
  deps not in `Generator/data` — (a) LHAPDF PDF sets (from the Spack `lhapdf`
  datadir) and (b) Pythia8's `xmldoc` (via `$PYTHIA8DATA`). Both are set/loaded
  by `setup_env.sh` from the Spack prefixes, which the worker also `spack load`s
  — but if a DIS job fails with a missing-PDF or Pythia8 "cannot find
  settings/particle data" error, that's the cause. CCQE/QEL/MEC splines don't
  touch either.
- **Flux.** `gevgen_worker.sh` does mono-energetic or flat-spectrum (`-e a,b`)
  only. A realistic (NuMI/DUNE) flux histogram needs `-f <flux>` staged and the
  gevgen `-f`/`-t` flux syntax — add if the validation samples require it.
- **Reweight.** A separate repo (`GENIE-MC/Reweight`), not built here and not
  used by `gmkspl`/`gevgen`. Add to `$GENIEBASE` + the tarball only if a
  weight-based systematics workflow needs it.
- **Microarch floor.** ROOT here is `-march=x86-64-v3` — the `.jobsub/config.json`
  `append_condor_requirements` (set at `init`, above) pins workers to v3. If jobs
  still SIGILL, check which lib with `objdump -d` on the fetched core, or drop to
  v2 by rebuilding ROOT (`SPACK_ROOT_SPEC` a v2 build, if one exists).
