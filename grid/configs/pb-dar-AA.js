// 208Pb, pion decay-at-rest ve, MARLEY v1 allowed approximation ("AA").
// Tokenized from examples/config/pb-dar.js in the marley-sign-fix-I127-Pb208
// tree; identical to pb-dar-v2.js except for form_factors.
//
// "AA" (also "allowed"/"aa") is matched in src/JSONConfig.cc and sets
// DiscreteNuclearReaction::allowed_approx_, which zeroes omega, kappa and Q^2
// in the matrix elements. There is no separate v1 reaction file for 208Pb --
// data/react/v1/ holds only 40Ar -- so the model choice is this key alone.
{
  seed: @SEED@,

  source: {
    type: "dar",
    neutrino: "ve",
  },

  // marley-v1
  form_factors: "AA",

  reactions: [ "ve208PbCC_Wakasa2012.react" ],

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
