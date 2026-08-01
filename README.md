# Kairos

Kairos is a deductive verification tool for synchronous reactive programs.
It takes a program and its temporal contracts (`assume`/`guarantee`), builds
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

## Typed predicates and private methods

Local predicates declare the type of every parameter. The same predicate can
be instantiated with current executable values or with historical expressions
inside specifications:

```kairos
predicate doseWouldExceed(total: int, sample: int) =
  total + sample > 1000;

// Current reaction
doseWouldExceed(totalDose, delivered)

// Specification view
doseWouldExceed(pre(totalDose), delivered)
```

Method parameters are read-only by default. Declare a parameter `inout` when
the method may assign it; an `inout` argument must be a variable reference:

```kairos
method add(inout target: int, amount: int) {
  target := target + amount;
}

add(totalDose, delivered + 1);
```

Predicates are expanded by the frontend. Methods remain private modular
procedures through Why3: their bodies are proved once, while call sites use
their `requires`, `ensures`, and inferred write frame. Methods return no value
and recursive method-call cycles are rejected.

Inside a method `ensures`, `old(expression)` denotes the value at method-call
entry. It is distinct from `pre(variable)`, which denotes the preceding
synchronous reaction and remains forbidden in method contracts. `old` is not
accepted in a method `requires` or outside a method postcondition.

Every `while` loop must declare an integer `variant`; Why3 proves that it
decreases and remains bounded.

An enum value can be dispatched with an exhaustive statement `match`:

```kairos
match mode with
| Idle { code := 0; }
| Running { code := 1; }
| Alarm { code := 2; }
end;
```

Without `_`, every constructor must occur exactly once. A final `_` branch may
cover the missing constructors. Kairos rejects a non-enum scrutinee, a
constructor from another enum, duplicate branches, non-exhaustive matches, and
branches made unreachable by `_`.

## Functional and temporal contracts

`requires` and `ensures` are local, non-temporal contracts for functions and
private methods. Node contracts use `assume` and `guarantee` because they
describe traces of synchronous reactions:

```kairos
contracts
  assume valid_samples: G(delivered >= 0);
  guarantee: G(alarmLatched = true => motorOn = false);
```

The contract name is optional. Temporal and history operators are accepted in
node assumptions and guarantees, but remain forbidden in method contracts.
`old` remains specific to method postconditions.

## Reusable specification definitions

Program-independent `spec def` declarations can live in a declaration-only
file and be imported relative to the importing source:

```kairos
import spec "spec/temporal_patterns.kairos";
```

An imported specification file may recursively import other specification
files, but may contain only `spec def` declarations and no nodes. The frontend
detects cyclic imports and duplicate definitions, then expands the imported
definitions before elaborating the program. This is compile-time reuse only:
it introduces neither node composition nor a modular proof boundary.

`init:` is an initialization pseudo-source, not a control state. It therefore
cannot receive an invariant and is not selected by `in states`. The frontend
lowers it to a private state for the existing execution and proof engines.
Node guarantees are interpreted from the first real state; the corresponding
initial `X` is inserted during lowering rather than written in contracts.

## Where test examples are located

- Expected **valid** examples: `tests/ok/`
- Expected **invalid** examples: `tests/ko/`
