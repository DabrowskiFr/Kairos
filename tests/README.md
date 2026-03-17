# Test Suites

This repository keeps the historical regression suites:

- `tests/ok/inputs`
- `tests/ko/inputs`

and also maintains a split view used by the current methodology:

- `tests/without_calls/ok/inputs`
- `tests/without_calls/ko/inputs`
- `tests/with_calls/ok/inputs`
- `tests/with_calls/ko/inputs`

## Classification Rule

- `with_calls` contains examples that use `call` or `import`, plus the support
  nodes that must still be compiled into `.kobj` objects for those examples.
- `without_calls` contains the rest of the regression corpus.

The split suites are copied from the historical `tests/ok/inputs` and
`tests/ko/inputs` trees so that older scripts and paths remain valid.

## Validation Commands

- Full historical campaign:
  - `scripts/validate_ok_ko.sh <repo> 5 legacy`
- Split campaigns:
  - `scripts/validate_ok_ko.sh <repo> 5 without_calls`
  - `scripts/validate_ok_ko.sh <repo> 5 with_calls`
  - `scripts/validate_ok_ko.sh <repo> 5 split`

## Environment Note

The current automata pipeline on branch `codex/spot-automata-migration`
requires the Spot CLI tools (`ltlfilt`, `ltl2tgba`) to be available on the
machine that runs the validation commands.
