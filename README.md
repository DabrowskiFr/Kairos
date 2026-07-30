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

## Generate portable C

Kairos can emit a C99 runtime for the executable node model:

```bash
dune exec -j 1 -- kairos --emit-c _build/embedded-c tests/ok/resettable_delay.kairos
```

The command writes:

```text
_build/embedded-c/kairos_generated.h
_build/embedded-c/kairos_generated.c
_build/embedded-c/kairos_generated_interface.json
```

The generated C is board-agnostic. Arduino, PlatformIO, sensor bindings, pin
mapping, and upload configuration should wrap these files from a separate
embedded project layer.

`kairos_generated_interface.json` describes every generated node, its typed
inputs and outputs, and the exact C ABI names. Embedded project generators
should consume this manifest instead of parsing the generated header.

## Compose nodes by mono-clock frontend inlining

Kairos supports a weak, static, mono-clock hierarchy which is completely
removed before the verification engine runs:

```kairos
import "threshold_filter.kairos";

node filtered_system(raw: int) returns (filtered: bool)
contracts
instances
  instance filter: threshold_filter;
states
  Init(init), Run;
transitions
  Init:
    to Run {
      call filter(raw) returns (filtered);
    }
  Run:
    to Run {
      call filter(raw) returns (filtered);
    }
end
```

The hierarchy elaborator:

- resolves imports relative to the importing file;
- gives every instance private control and data state;
- renames and retains internal contracts and invariants;
- emits only unreferenced root nodes;
- eliminates all `instance` and `call` constructs after preliminary frontend
  validation and before proof planning or C generation.

This is monolithic verification, not modular proof. All instances share the
owner's clock: each static instance must be called exactly once on every
transition, in the same order and with the same variable-to-port bindings.
Calls cannot be nested, conditional, or recursive. Conditional behaviour is
expressed through ordinary inputs (for example, an explicit `enable` input),
while feedback uses a caller-owned snapshot variable so that a tick delay is
visible in the Kairos source.

## Where test examples are located

- Expected **valid** examples: `tests/ok/`
- Expected **invalid** examples: `tests/ko/`
