// 127I, pion decay-at-rest ve, MARLEY v2 form factors.
// Tokenized from examples/config/i-dar.js in the marley-sign-fix-I127-Pb208
// tree. @SEED@ / @NEVENTS@ / @OUTSTEM@ are substituted per process by
// grid/workers/marley_worker.sh: `marley generate` takes a config file and
// nothing else, so the seed and event count cannot be passed on the command
// line. The upstream `seed: 877` would make every grid job byte-identical.
{
  seed: @SEED@,

  source: {
    type: "dar",
    neutrino: "ve",
  },

  // marley-v2
  form_factors: {
    sachs_model: "bbba05",
    axial_model: "dipole",
    nuclear_model: "klein",
    nucl_options: { adapted: true },
  },

  reactions: [ "ve127ICC_Palarczyk1999.react" ],

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
