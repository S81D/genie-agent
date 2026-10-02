// 40Ar, muon decay-at-rest ve, MARLEY v2 models, with a 100-universe
// strength-variation multisim on the discrete channel.
// Tokenized from the user's muDAR.js: only the "multisim" weight calculator
// is kept (its "shift" and optical_model entries are dropped), and the output
// is switched from ascii to root to match marley_worker.sh.
// @SEED@ / @NEVENTS@ / @OUTSTEM@ are substituted per process by
// grid/workers/marley_worker.sh.
{
  seed: @SEED@,

  target: {
    nuclides: [ 1000180400 ],
    atom_fractions: [ 1.0 ],
  },

  // marley-v2: HF-CRPA continuum + Bhattacharya2009 discrete. With no
  // form_factors key MARLEY adopts its v2 defaults (bbba05 / dipole / klein),
  // i.e. the same models that i-dar-v2.js / pb-dar-v2.js set explicitly.
  reactions: [
    "ve40ArCC_HF-CRPA.react",
    "ve40ArCC_Bhattacharya2009-Discrete.react"
  ],

  // "decay-at-rest" and "dar" are the same branch in JSONConfig.cc, so this
  // is the same ve spectrum as the 127I/208Pb campaign.
  source: {
    type: "decay-at-rest",
    neutrino: "ve",
  },

  direction: { x: 0.0, y: 0.0, z: 1.0 },

  // 100 random-draw universes of the discrete B(F)/B(GT) values ->
  // weights "MultisimVar_0" ... "MultisimVar_99", stored beside "CV".
  weights: [
    { type: "strength_variation",
      name: "MultisimVar",
      mode: "multisim",
      num_variations: 100,
      // FIXED on purpose, never @SEED@: this seeds the draw of the universes
      // themselves (once per job). Every job must draw the same 100 universes,
      // or MultisimVar_k is a different throw in each file and merging the
      // jobs shrinks the universe-to-universe spread.
      seed: 54321,
      reaction_file: "ve40ArCC_Bhattacharya2009-Discrete.react" }
  ],

  generate: {
    events: @NEVENTS@,
    output: [
      { file: "@OUTSTEM@.hepmc3.root",
        format: "root",
        mode:"overwrite",
        // no tty on a grid worker: without force an existing file would prompt
        force: true,
      }
    ]
  },
}
