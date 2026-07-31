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

## Typed predicates and actions

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

Action parameters are read-only by default. Declare a parameter `inout` when
the action may assign it; an `inout` argument must be a variable reference:

```kairos
action add(inout target: int, amount: int) {
  target := target + amount;
}

add(totalDose, delivered + 1);
```

Predicates and actions are expanded by the frontend. Action contracts remain
inline assertions at the call site; they do not introduce a separate
pre-state operator or modular proof boundary.

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

## Outputs derived from control state

A boolean output that is completely determined by the node's control state can
be declared with `derive` immediately after the `states` declaration:

```kairos
states Idle, Running, Alarm;
derive motorOn = state in Running;
derive alarmLatched = state in Alarm;

transitions
  init:
    to Idle { skip; }
  // ...
```

The output remains part of the node's `returns` interface, but source code
cannot assign it. On every explicit transition, the frontend assigns the value
selected by the destination state before executing the transition body. It also
generates the corresponding non-initial state invariants. This is surface
syntax only: the core execution and proof engines continue to process an
ordinary single-node program.

`init:` is an initialization pseudo-source, not a control state. It therefore
cannot receive an invariant and is not selected by `in states`. The frontend
lowers it to a private state for the existing execution and proof engines.
Node guarantees are interpreted from the first real state; the corresponding
initial `X` is inserted during lowering rather than written in contracts.

Use `derive` only for scalar boolean outputs with no memory independent of the
control state. Quantities such as counters, accumulated doses, or timers remain
ordinary assigned outputs or locals.

## Where test examples are located

- Expected **valid** examples: `tests/ok/`
- Expected **invalid** examples: `tests/ko/`
