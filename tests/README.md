Tests layout

- ok/: expected to pass (run by `dune runtest`)
- ko/: expected to fail (run by `dune runtest` with `!` in cram)
- fail/: known failures (not run by default)

Inputs
- ok/inputs/*.obc are all proved with `--prove`
- ko/inputs/*.obc are expected to fail (parse/verify)

Commands
- Run default tests:  dune runtest
- Promote snapshots:  dune runtest --auto-promote
- Run known-failing:  dune runtest --alias=runtest-fail
