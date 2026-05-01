# Kairos

Kairos is a deductive verification tool for synchronous reactive programs.
It takes a program and its temporal contracts (`requires`/`ensures`), builds
an intermediate verification representation, and generates local proof
obligations checked with a standard verification backend.

## Run the validation campaign

Full campaign (15 jobs, 1s timeout per VC, 15s timeout per file):

```bash
./scripts/validate_ok_ko.sh --jobs 15 --timeout-goal 1 --timeout-file 15
```

Reports are written to:

```text
_build/validation/
```

## Verify a specific program

Proof command for a `.kairos` file:

```bash
dune exec -j 1 -- kairos --prove --timeout-s 1 <chemin/vers/programme.kairos>
```

Example:

```bash
dune exec -j 1 -- kairos --prove --timeout-s 1 tests/ok/resettable_delay.kairos
```

To list all available CLI commands and options:

```bash
dune exec -j 1 -- kairos --help
```

## Where test examples are located

- Expected **valid** examples: `tests/ok/`
- Expected **invalid** examples: `tests/ko/`

