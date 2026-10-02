// Tokenized MARLEY job configuration for grid running.
//
// @SEED@ / @NEVENTS@ / @OUTSTEM@ are substituted by grid/workers/marley_smoke.sh
// into $PWD/job_config.js on the worker. This indirection is necessary because
// `marley generate` takes a config file and nothing else — the random seed and
// the event count are configuration KEYS, not command-line flags, so a grid job
// cannot vary them per process any other way.
//
// Physics: the recommended MARLEY v2 configuration for charged-current
// nu_e + 40Ar, as described in examples/config/COPY_ME.js upstream.
{
  seed: @SEED@,          // nonnegative 63-bit integer

  // Pure 40Ar target
  target: {
    nuclides: [ 1000180400 ],
    atom_fractions: [ 1.0 ],
  },

  reactions: [
    // CC on the nucleus, using the recommended v2 cross-section models for
    // continuum (HF-CRPA) and discrete (Bhattacharya2009) nuclear transitions
    "ve40ArCC_HF-CRPA.react",
    "ve40ArCC_Bhattacharya2009-Discrete.react",
    // Elastic scattering on atomic electrons
    "ES.react"
  ],

  // Pinched Fermi-Dirac supernova-like spectrum
  source: {
    type: "fermi-dirac",
    neutrino: "ve",
    Emin: 0,             // MeV
    Emax: 60,            // MeV
    temperature: 3.5,    // MeV
    eta: 4               // pinching parameter (dimensionless)
  },

  // Incident neutrino direction 3-vector
  direction: { x: 0.0, y: 0.0, z: 1.0 },

  generate: {
    events: @NEVENTS@,

    // Two streams: the HepMC3 ASCII record (NuHepMC v1.0.0 compliant, readable
    // by any HepMC3 application) and the compressed ROOT TTree
    // "MARLEY_event_tree" (readable without MARLEY's shared libraries).
    //
    // force: true is REQUIRED on a batch worker. Without it, an already-existing
    // output file makes marley prompt interactively before overwriting — and
    // there is no tty on a grid node to answer.
    output: [
      { file: "@OUTSTEM@.hepmc3", format: "ascii", mode: "overwrite", force: true },
      { file: "@OUTSTEM@.root",   format: "root",  mode: "overwrite", force: true },
    ],
  },
}
