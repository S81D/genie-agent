# Standalone MARLEY v2 grid production (jobsub-lite + RCDS)

Run upstream **standalone MARLEY** on the Fermigrid, alongside the GENIE payload
documented in [README.md](README.md): ship the build as an RCDS/CVMFS tarball,
drive jobs with the same self-contained `jobsub-lite` skill. No container, no
pixi.

**This is a second payload, not a GENIE build option.** rc-v380's `./configure`
has no `--enable-marley` (that flag was fork-only — see the header of
`build/do_configure.sh`), and there are no MARLEY sources under `Generator/`. So
MARLEY gets its own clone, its own tarball, and its own label in the *shared*
`.jobsub` catalog.

**Build config:** ROOT enabled (for the `root` event output format and
`marley summarize`), GSL and HepMC3 from MARLEY's own bundled copies.

## GPVM layout

MARLEY lives in **`MARLEYBASE = /exp/dune/app/users/doran/grid/MARLEY`**, a
sibling of the GENIE base:

```
/exp/dune/app/users/doran/grid/
├── GENIE/                        $GENIEBASE (see README.md)
│   ├── .jobsub/                  shared state — catalog.json holds BOTH labels
│   └── grid/                     this tree
│       ├── build/{setup_marley_env.sh, build_marley.sh, ...}
│       ├── configs/ve40Ar_fd.js  tokenized job config
│       ├── workers/marley_smoke.sh
│       └── jobsub-lite/
└── MARLEY/                       $MARLEYBASE
    ├── marley/                   git clone -b main https://github.com/MARLEY-MC/marley.git
    ├── setup_marley_env.sh       copied from grid/build/  (also in the tarball)
    ├── configs/                  copied from grid/        (also in the tarball)
    ├── MARLEY_COMMIT.txt         the exact main SHA
    ├── spack_loaded.txt
    └── build.log
```

Get the pieces onto the GPVM (the workstation and GPVM trees are disjoint):

```sh
BASE=/exp/dune/app/users/doran/grid/GENIE
scp grid/build/setup_marley_env.sh grid/build/build_marley.sh  dunegpvm:$BASE/grid/build/
scp grid/workers/marley_smoke.sh                               dunegpvm:$BASE/grid/workers/
scp -r grid/configs                                            dunegpvm:$BASE/grid/
scp grid/README_marley.md                                      dunegpvm:$BASE/grid/
ssh dunegpvm "chmod +x $BASE/grid/build/build_marley.sh $BASE/grid/workers/marley_smoke.sh"
```

`chmod +x` on the worker matters — `jobsub.py submit` rejects a worker that is
not executable.

Session preamble, from `$GENIEBASE` on a **dunegpvm**:

```sh
cd /exp/dune/app/users/doran/grid/GENIE
export GENIEBASE=$PWD
export MARLEYBASE=/exp/dune/app/users/doran/grid/MARLEY
export JOBSUB_STATE_DIR=$GENIEBASE/.jobsub    # so commands work from either tree
SKILL=grid/jobsub-lite
```

`.jobsub/` is normally located by walking up from the CWD. Setting
`JOBSUB_STATE_DIR` explicitly means the MARLEY commands resolve the same catalog
even when run from `$MARLEYBASE`, so both payloads share one `catalog.json`.

---

## 0. Auth (once per session)

Identical to [README.md](README.md) §0 — `kinit`, `htgettoken`, and system
`python3` (never pixi/conda).

Driving this from a workstation over ssh: `ssh -K dunegpvm06.fnal.gov` forwards
your local Kerberos TGT (GSSAPI delegation), after which
`htgettoken -a htvaultprod.fnal.gov -i dune` authenticates to the vault with
that ticket and stores the bearer token non-interactively — no browser flow. A
plain `ssh` leaves the GPVM with no ticket and no token, and every jobsub call
fails.

Use a **login** shell for anything that calls jobsub (`ssh -K <host> bash -l -s`,
not `bash -s`). `/etc/profile.d/jobsub_lite.sh` is what sets
`JOBSUB_DROPBOX_SERVER_LIST="rcds01.fnal.gov rcds02.fnal.gov"`, and a
non-login shell never sources it — `publish` then dies deep in the RCDS upload
with `NoPublisherHandlerServerError: No server was specified to publish the
tarball`, long after the token checks have all passed. Interactive sessions get
this for free, which is why it only bites automation.

---

## 1. Build MARLEY

`setup_marley_env.sh` pins the same `spack-fnal-v1.1.0` instance as the GENIE
script, but loads only **two** packages: `gcc@12.5.0` and `root@6.28.12`. The
gcc pin is not about C++17 (AL9's system gcc@11.5.0 would satisfy that) — it is
about matching the ABI of the ROOT that MARLEY links, whose libstdc++ needs
`GLIBCXX_3.4.30`.

```sh
bash grid/build/build_marley.sh          # minutes, not the 30-60 GENIE takes
```

It clones `marley/` if absent, copies `setup_marley_env.sh` + `configs/` up to
`$MARLEYBASE` (so both land at the tarball top level), records the SHA to
`MARLEY_COMMIT.txt`, and runs:

```sh
make -j$JOBS IGNORE_GSL=1 IGNORE_HEPMC3=1
```

`IGNORE_ROOT` is deliberately absent: MARLEY auto-enables its ROOT interface
when `root-config` is on `PATH`, which `thisroot.sh` guarantees.
`IGNORE_GSL`/`IGNORE_HEPMC3` select MARLEY's bundled copies so the payload
carries no extra Spack runtime deps.

Record the SHA in the campaign log; to freeze a production campaign check that
SHA out explicitly (`cd $MARLEYBASE/marley && git checkout <sha>`) and rebuild
with `CLEAN=1`.

Build hiccups:
- **No cmake, or too old.** The top-level `Makefile` auto-detects CMake and
  falls back to `make/build.mk` when it is absent; if the GPVM's cmake is
  present but unusable, add `IGNORE_CMAKE=1` to the `make` line.
- **Changed `IGNORE_*` flags have no effect.** CMake caches them under
  `build/CMakeFiles`; run `make reconfigure` (or `CLEAN=1`).

---

## 2. Post-build env check

The two things most likely to break on a worker, both catchable here:

```sh
source $MARLEYBASE/setup_marley_env.sh
marley version

# libstdc++ must resolve under the CVMFS gcc@12.5.0 prefix, NOT /usr/lib64.
ldd $MARLEYBASE/marley/build/bin/marley | grep -E 'libstdc\+\+|not found'

# Every prefix must be under /cvmfs/.../spack-fnal-v1.1.0/ — an /exp or $HOME
# overlay prefix cannot ride in the grid tarball.
spack find --loaded --format '{name}@{version}  {prefix}'
```

Then a real local run, which proves `$MARLEY` resolves the `.react` /
`structure` / `optical_model` search path and that **both** writers work:

```sh
sed -e 's/@SEED@/12345/' -e 's/@NEVENTS@/20/' -e 's/@OUTSTEM@/t/' \
    $MARLEYBASE/configs/ve40Ar_fd.js > /tmp/t.js
cd /tmp && marley generate /tmp/t.js
ls -l /tmp/t.hepmc3 /tmp/t.root
```

---

## 3. Tarball → publish → catalog

`init` has already been run for the GENIE payload; the same
`.jobsub/config.json` applies, including
`append_condor_requirements '(TARGET.Microarch>="x86_64-v3")'`. That pin is
still correct here — we link ROOT, which is built `-march=x86-64-v3`.

```sh
python3 $SKILL/scripts/jobsub.py tarball build --build-dir "$MARLEYBASE" \
    --include marley setup_marley_env.sh configs \
    --exclude-component src --exclude-component .git --exclude-component CMakeFiles \
    --exclude-suffix .o --exclude-suffix .d --exclude-suffix .a \
    --name-prefix marley_v2_main
#  keeps marley/{build/bin,build/lib,data,examples,include,setup_marley.sh}.
#  Measured 43.3 MB (vs GENIE's 428 MB) — src/, .git and CMakeFiles dropped —
#  so no --background needed.

python3 $SKILL/scripts/jobsub.py publish \
    --tarball .jobsub/tarballs/marley_v2_main_*.tar --label marley_v2_main
#  runs ONE sentinel grid job to discover the CVMFS path — ~5-20 min.

python3 $SKILL/scripts/jobsub.py verify --label marley_v2_main     # -> ok
python3 $SKILL/scripts/jobsub.py labels                            # both labels
```

---

## 4. Smoke test — one job, full pipeline

`marley_smoke.sh` runs `marley version → generate → summarize` in a single job.

The structural difference from the GENIE workers: **it writes its own config.**
`marley generate` takes a config file and nothing else — the random seed and
event count are configuration *keys*, not command-line flags — so the worker
substitutes `@SEED@` / `@NEVENTS@` / `@OUTSTEM@` from `configs/ve40Ar_fd.js`
into `$PWD/job_config.js` and `cat`s the result into the log. `-c` also accepts
an absolute path, so a config staged with `jobsub ... -f` (landing in
`$CONDOR_DIR_INPUT`) overrides the shipped one without republishing. (That
path is only known on the worker; `marley_worker.sh` resolves a **bare** file
name against `$CONDOR_DIR_INPUT` instead — see §6.)

```sh
python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/marley_smoke.sh \
    -N 1 --runtype marley --tar-label marley_v2_main \
    --memory 2000MB --expected-lifetime 2h --disk 10GB --output-suffix .root \
    -- -R @TAR_DIR@ -O @PNFS_OUT@ -c configs/ve40Ar_fd.js -n 200
#  --dry-run first.
```

`--memory` / `--expected-lifetime` here are **estimates, not measured** — MARLEY
is a tens-of-MeV single-nucleus generator and should be light, but size any
production job from `/usr/bin/time -v` MaxRSS on this smoke + ~30 %, per §5 of
[README.md](README.md).

`@TAR_DIR@` → published CVMFS dir; `@PNFS_OUT@` → default
`/pnfs/dune/scratch/users/$USER/jobsub-lite/marley/<stem>`.

```sh
python3 $SKILL/scripts/jobsub.py status   <jobid>
python3 $SKILL/scripts/jobsub.py fetchlog <jobid>       # .out must end with DONE
python3 $SKILL/scripts/jobsub.py pull     <jobid> --suffix .root
python3 $SKILL/scripts/jobsub.py pull     <jobid> --suffix .hepmc3
```

Success is all five of:

1. `status` → `done`.
2. The fetched `.out` has all three `=== [n/3] ===` markers and ends with `DONE`.
3. The echoed `job_config.js` shows the substituted seed and event count, with
   no leftover `@` tokens.
4. Both `.root` files and the `.hepmc3` pull back non-empty.
5. The event `.root` opens in ROOT with a non-empty `MARLEY_event_tree`, and
   `head` on the `.hepmc3` shows the HepMC3 ASCII header.

---

## 5. Production campaign — π-DAR νe on ¹²⁷I and ²⁰⁸Pb

A second payload, built from the local **`marley-sign-fix-I127-Pb208`** tree
(`MARLEY-MC/marley-private`, branch `sign-fix`) rather than the public clone.
Target: **500 k events per (target × model)** — 10 jobs × 50 k — over the 2×2
matrix {¹²⁷I, ²⁰⁸Pb} × {v2 form factors, v1 allowed approximation "AA"}.
**40 jobs, 2 M events, ≈ 4.5 GB.**

Two things differ from §§1–4 above, both deliberate.

### 5a. Delivery is `-f`, not RCDS/CVMFS

This payload is **not published**. RCDS writes to
`/cvmfs/fifeuser*.opensciencegrid.org`, which is world-readable, and this is a
private, unreleased build. Instead the tarball is staged once to the user's own
dCache area and pulled per job:

```sh
python3 $SKILL/scripts/jobsub.py submit ... -f /pnfs/.../marley_v2_0_1_signfix.tar
```

`marley_worker.sh` finds it in `$CONDOR_DIR_INPUT` and unpacks it into job
scratch. Its top-level members (`marley/`, `setup_marley_env.sh`, `configs/`)
are the same layout RCDS produced, so `setup_marley_env.sh` is unchanged
between the two delivery modes.

Consequences: **no `publish`, no `verify`, no catalog label**, and **no
`-R @TAR_DIR@`** in the worker args — without a `--tar-label`, `jobsub.py`
substitutes `@TAR_DIR@` with an empty string (it warns, but only warns).
Staging by hand rather than `-f file://…` is also deliberate: it keeps the
payload in a known dCache location with no chance of routing through the RCDS
dropbox.

### 5b. The source tree is uploaded, not cloned

```sh
M=/exp/dune/app/users/doran/grid/MARLEY_SIGNFIX
ssh -K dunegpvm06.fnal.gov "mkdir -p $M"
rsync -av --exclude 'build/' \
    /Users/doran/Desktop/software/marley-sign-fix-I127-Pb208/ \
    dunegpvm06.fnal.gov:$M/marley/
```

The working tree must ship **as-is — never `git clone` or `git archive`**:

- `src/TabulatedXSec.cc` is uncommitted *and required to compile*. HEAD renamed
  `get_particle_helicity`→`get_particle_chirality` but left the old call site,
  so a clean checkout of the branch does not build.
- `data/react/ve127ICC_Palarczyk1999.react`,
  `data/react/ve208PbCC_Wakasa2012.react` and the two `.js` configs are
  **untracked** — git-based packaging drops them silently and the jobs then
  fail with "reaction file not found".

`build/` is the only exclusion: macOS arm64 binaries with a `CMakeCache.txt`
pinned to `/Users/…` and homebrew ROOT, which would break the Linux build. It
is regenerated output, not a physics input. Everything else ships intact,
including `data/react/crpa/`.

`build_marley.sh` is reused **unchanged** — it skips the clone when `marley/`
already exists, so the rsync'd tree is picked up as-is:

```sh
export MARLEYBASE=/exp/dune/app/users/doran/grid/MARLEY_SIGNFIX
bash grid/build/build_marley.sh
source $MARLEYBASE/setup_marley_env.sh
marley version          # expect 9a6fff0-dirty (no .VERSION file -> git short SHA)
```

Then tarball and stage (note the absent `--exclude-component src`):

```sh
export JOBSUB_STATE_DIR=$GENIEBASE/.jobsub
python3 $SKILL/scripts/jobsub.py tarball build --build-dir "$MARLEYBASE" \
    --include marley setup_marley_env.sh configs \
    --exclude-component .git --exclude-component CMakeFiles \
    --exclude-suffix .o --exclude-suffix .d --exclude-suffix .a \
    --name-prefix marley_v2_0_1_signfix

PAY=/pnfs/dune/scratch/users/$USER/payloads
ifdh mkdir_p $PAY
ifdh cp -D $GENIEBASE/.jobsub/tarballs/marley_v2_0_1_signfix_*.tar $PAY/
```

### 5c. The job matrix

"AA" is **a config toggle, not a different reaction file** — `data/react/v1/`
holds only 40Ar. Both targets are ProcessType `0` discrete B(GT)/B(F) tables
served by `DiscreteNuclearReaction`; `form_factors: "AA"` sets
`allowed_approx_`, zeroing ω, κ and Q². So one build and one react file per
target, with four configs differing along exactly two axes:

| cell | config | `--pnfs-out` under `…/marley_dar/` | `-t` |
|---|---|---|---|
| ¹²⁷I v2 | `configs/i-dar-v2.js` | `127I/v2` | `I-dar-v2` |
| ¹²⁷I AA | `configs/i-dar-AA.js` | `127I/AA` | `I-dar-AA` |
| ²⁰⁸Pb v2 | `configs/pb-dar-v2.js` | `208Pb/v2` | `Pb-dar-v2` |
| ²⁰⁸Pb AA | `configs/pb-dar-AA.js` | `208Pb/AA` | `Pb-dar-AA` |

The configs carry `@SEED@` / `@NEVENTS@` / `@OUTSTEM@`. Tokenizing the seed is
not cosmetic: the upstream configs hardcode `seed: 877`, which would make all
40 jobs generate byte-identical events.

**Smoke first — one job, small stats:**

```sh
python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/marley_worker.sh \
    -N 1 --runtype marley_dar -f $PAY/marley_v2_0_1_signfix_*.tar \
    --memory 4000MB --expected-lifetime 2h --disk 10GB --output-suffix .root \
    --pnfs-out /pnfs/dune/scratch/users/$USER/marley_dar/smoke \
    -- -O @PNFS_OUT@ -c configs/pb-dar-v2.js -n 2000 -t Pb-dar-v2-smoke
```

Record MaxRSS and walltime from it, extrapolate ×25 to 50 k, and only then
launch each cell with `-N 10 -n 50000`. Seeds cannot collide across the four
submissions: `CLUSTER*100000 + PROCESS` is unique per submission.

Each job writes `<tag>_p<proc>_c<cluster>.hepmc3.root` (the event tree),
`.summary.root` (the flat `mst` tree from `marley summarize`), and
`job_config.js` — so the exact seed that produced each file sits beside it.
Both outputs end in `.root`, so `--output-suffix .root` counts completions
correctly; separate them on pull with `--suffix .hepmc3.root` and
`--suffix .summary.root`.

Outputs land on `/pnfs` scratch (~30 d GC); grid workers cannot see `/exp`, so
the move to `/exp/dune/data/users/$USER/samples/v2.0.1/{127I,208Pb}` is a
manual step afterwards.

---

## 6. Production campaign — μ-DAR νe on ⁴⁰Ar with multisim weights

**500 k events** on ⁴⁰Ar — 10 jobs × 50 k — v2 models only (HF-CRPA continuum +
Bhattacharya2009 discrete), each event carrying 100 `strength_variation`
multisim weights `MultisimVar_0 … MultisimVar_99` beside `CV`. Config:
`configs/ar-dar-v2.js`. Its source (`"decay-at-rest"`) is the same
`JSONConfig.cc` branch as §5's `"dar"`, so this is the same νe spectrum.

### 6a. Same payload as §5

The §5 sign-fix tarball is reused **unchanged**. Commit 9a6fff0 flips the sign
of `vTprime` in `DiscreteNuclearReaction::diff_xs`, which also serves the ⁴⁰Ar
discrete channel — public `main` does not carry that fix. Reuse also means the
Ar sample comes from the bit-identical build behind the I/Pb samples.

The tarball's `configs/` predates this config, so rather than rebuild and
re-stage, the config rides as a **second `-f`** and is passed to the worker as a
bare file name (`-c ar-dar-v2.js`). `marley_worker.sh` resolves `-c` three ways:
leading `/` → absolute; contains `/` → payload-relative (all §5 submissions);
bare name → `$CONDOR_DIR_INPUT`, where `jobsub -f` drops staged files.

### 6b. The weight seed is fixed, not per-job

Only the top-level `seed` is tokenized. The `seed: 54321` **inside the
`weights` block stays the same in every job**, deliberately. It seeds the RNG
that draws each universe's B(GT)/B(F) set once per job
(`StrengthVariationWeightCalculator::ensure_initialized`), in a fixed order. A
per-job weight seed would make `MultisimVar_k` a different throw in every file,
and merging 10 jobs would shrink the universe spread of the discrete component
by ~√10.

Universes are reproducible across grid jobs (same binary, same CVMFS
libstdc++), but **not** guaranteed to match a local macOS run with the same
seed — `std::normal_distribution` is implementation-defined (libc++ vs
libstdc++). Compare CV quantities with local runs, not individual universes.

Only the 11 bound ⁴⁰K levels (all with non-zero errors) are varied, so CRPA
continuum events (`proc` 101) carry weight 1 in every universe; only discrete
events (`proc` 100) move.

### 6c. Stage the config, smoke, launch

```sh
PAY=/pnfs/dune/scratch/users/$USER/payloads
ifdh ls $PAY                  # the §5 sign-fix tar must still be there (scratch GC)
ifdh cp -D $GENIEBASE/grid/configs/ar-dar-v2.js $PAY/

python3 $SKILL/scripts/jobsub.py submit --worker grid/workers/marley_worker.sh \
    -N 1 --runtype marley_dar \
    -f $PAY/marley_v2_0_1_signfix_*.tar -f $PAY/ar-dar-v2.js \
    --memory 2000MB --expected-lifetime 2h --disk 10GB --output-suffix .root \
    --pnfs-out /pnfs/dune/scratch/users/$USER/marley_dar/40Ar/smoke \
    -- -O @PNFS_OUT@ -c ar-dar-v2.js -n 2000 -t Ar-dar-v2-smoke
#  --dry-run first, placed BEFORE the "--": everything after "--" goes to the
#  worker, so a trailing --dry-run really submits (and getopts exits 2 on it).
#  Not §5's marley_dar/smoke: its 0000/ already holds the Pb smoke's
#  job_config.js, and dCache won't overwrite it.
```

Smoke passes when, beyond the §4 criteria: the echoed `job_config.js` shows the
numeric top-level seed **and still `seed: 54321`** in `weights`; the log reports
a flux-averaged total cross section of **2.8326 × 10⁻⁴⁰ cm²** per atom (measured
locally, seed-independent); and `mst` has a 100-entry `other_weights`, non-trivial
only for `proc` 100.

Local sizing (sign-fix build, Apple silicon): ~4 s init + ~0.43 ms/event, 271 MB
MaxRSS, ~1.0 kB/event across both files (~0.5 GB for 500 k). Set production
`--memory` / `--expected-lifetime` from the smoke's MaxRSS and walltime + 30 %,
then launch with `-N 10 -n 50000 -t Ar-dar-v2` and
`--pnfs-out /pnfs/dune/scratch/users/$USER/marley_dar/40Ar/v2`. Seeds
(`CLUSTER*100000 + PROCESS`) are disjoint from the §5 clusters.

After production, run `grid/local/check_multisim.C` on the output dir before
merging or moving anything. It requires every job to agree weight-for-weight on
each (level, universe) pair, with discrete events keyed by `Ex`. It also checks
names, xsec, continuum weights and distinct seeds, and prints the universe
spread of σ. A job made with a different weight seed shows up as 1100
mismatches. Final home: `/exp/dune/data/users/$USER/samples/v2.0.1/40Ar`
(manual copy, as §5).

---

## Known follow-ups

- **Production worker.** This tier is smoke-only. A `marley_worker.sh` for real
  statistics should reuse the same config templating with a `-c` pointing at a
  campaign config, and scale with `-N`; seeds stay unique across submissions
  because `CLUSTER*100000 + PROCESS` does.
- **Compress the ASCII stream.** HepMC3 ASCII is bulky. At production statistics
  either `gzip` before `ifdh cp`, or drop the `ascii` entry from the config's
  `output` array and keep only `format: "root"`.
- **uproot readability is unverified.** `MARLEY_event_tree` stores the HepMC3
  `GenEventData` structure; upstream promises only that *ROOT* can read it
  without MARLEY's shared libraries. If uproot struggles with that layout, the
  flat TTree from `marley summarize` is the fallback — which is why the smoke
  produces one.
- **Unexercised subcommands.** `marley xsec`, `reweight`, `decay`, `convert` and
  `print` are all in the v2 executable and none are covered here.
- **RCDS GC ~30 d / scratch dCache GC ~30 d.** Same as GENIE — see §5 of
  [README.md](README.md); `publish ... --overwrite` re-pushes an identical tree.
