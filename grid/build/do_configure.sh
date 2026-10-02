#!/usr/bin/env bash
#
# Configure a MINIMAL GENIE v3.8 (rc-v380) build: PYTHIA8 + LHAPDF6 only.
#
# Run from inside $GENIE (the Generator/ checkout), after `source ../setup_env.sh`.
# build_genie.sh does this for you.
#
# rc-v380 defaults: pythia8 ON, lhapdf5 ON. We keep pythia8 (the rc-v380
# hadronizer default and the only path that compiles) and switch lhapdf5->6.
# The MARLEY / HepMC3 / --enable-rwght / --enable-gsl / --enable-boost flags from
# the old project do NOT exist in rc-v380's ./configure (fork-only); GSL comes
# transitively via ROOT's MathMore, which ./configure verifies is present.
set -euo pipefail

# lhapdf-config / log4cpp-config land on PATH via `spack load` (setup_env.sh).
export LHAPDF_INC="${LHAPDF_INC:-$(lhapdf-config --incdir)}"
export LHAPDF_LIB="${LHAPDF_LIB:-$(lhapdf-config --libdir)}"
export LOG4CPP_INC="${LOG4CPP_INC:-$(log4cpp-config --prefix)/include}"
export LOG4CPP_LIB="${LOG4CPP_LIB:-$(log4cpp-config --libdir)}"

./configure \
  --with-optimiz-level=O2 \
  --enable-pythia8  --disable-pythia6 \
  --enable-lhapdf6  --disable-lhapdf5 \
  --with-pythia8-lib="${PYTHIA8_LIB}" \
  --with-pythia8-inc="${PYTHIA8_INC}" \
  --with-lhapdf6-inc="${LHAPDF_INC}" \
  --with-lhapdf6-lib="${LHAPDF_LIB}" \
  --with-log4cpp-inc="${LOG4CPP_INC}" \
  --with-log4cpp-lib="${LOG4CPP_LIB}" \
  --with-libxml2-inc="${LIBXML2}/include/libxml2" \
  --with-libxml2-lib="${LIBXML2}/lib"
