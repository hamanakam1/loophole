# Contributing

Loophole is a small open-source experiment. Keep contributions understandable,
reproducible, and honest about what the model does and does not establish.

## Development

Use Gleam 1.19.2 and Node.js 22+. Follow the README setup, then run
`npm run check` before proposing a change. For UI changes, rebuild and check the
app in a desktop and narrow mobile viewport. Include a screenshot if useful.

The main files are:

- `src/loophole/engine.gleam`: pure simulation and finite strategy search.
- `src/loophole.gleam`: experiment selection and the original compute interface.
- `src/loophole/reputation.gleam`: pure reputation, collateral, and default model.
- `src/loophole/reputation_ui.gleam`: reputation controls, visualization, and receipt serialization.
- `src/loophole/collusion.gleam`: pure review weighting, budget accounting, and finite search.
- `src/loophole/collusion_ui.gleam`: review controls, crowd visualization, and receipt serialization.
- `test/collusion_test.gleam`: inflation, mitigation limits, accounting, and search invariants.
- `src/loophole/browser.mjs`: browser-only file download and hash access.
- `test/loophole_test.gleam` and `test/reputation_test.gleam`: model behavior and invariants.
- `test/replay-verifier.test.mjs`: receipt compatibility and tamper rejection.
- `public/style.css`: responsive visual design.

## Reporting a bug

Include the replay link or exported JSON, browser/version, expected result, and
actual result. Use synthetic examples; do not submit private production data.

## Adding an experiment

Open an issue describing the rule, incentive, candidate strategy space, and a
small demonstrable failure before making a large change. Keep transitions pure
and deterministic. Add a test that demonstrates the failure and checks any
proposed repair. Label bounded search as bounded search.

Please keep discussion kind and specific. Critique ideas and code, not people.
By contributing, you agree to license your contribution under the project's MIT
license.
