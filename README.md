# Kairos

Kairos is a deductive verification tool for synchronous reactive programs.
It takes a program and its temporal contracts (`assume`/`guarantee`), builds
an intermediate verification representation, and generates local proof
obligations checked with a standard verification backend.

Contributor documentation: [conventions](CONTRIBUTING.md) and
[architecture](ARCHITECTURE.md).

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

Symbolic body-effect summaries are disabled by default. To opt in:

```bash
dune exec -j 1 -- kairos --prove --body-effect-summaries tests/ok/resettable_delay.kairos
```

This option adds facts computed from reaction bodies to incoming product
characteristics and checks their preservation. Without it, temporal guards,
user annotations, history transport, and guarantee progress/preservation
remain active. The reference profile (`--no-proof-optimizations`) also leaves
body-effect summaries disabled; an explicit `--body-effect-summaries` overrides
that default. The option affects proof generation, not executable behavior.

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

Pure-function calls are regular expression atoms. They can be nested and used
as operands in executable expressions as well as in historical formulas:

```kairos
function inc(x: int): int = x + 1;

// Executable expression
out := inc(inc(input)) + 1;

// Historical formula
guarantee: G(out = inc(input) + 1);
```

The frontend resolves a call according to its context and declaration, then
checks its arity, argument types, and result type. A boolean function or
predicate call can therefore be used directly as a condition or formula.

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

Nodes are deliberately flat: the source language has no `instances` section
and no `call child(...) returns (...)` statement. An expression call denotes a
pure function or predicate; a standalone `name(...);` statement denotes a
method call. Node composition is not part of the current language.

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
  guarantee: G(alarmLatched => not motorOn);
```

The contract name is optional. Temporal and history operators are accepted in
node assumptions and guarantees, but remain forbidden in method contracts.
`old` remains specific to method postconditions.

Executable `pre(reference)` is restricted to observer expressions. It is not
accepted in function bodies, transition guards or bodies, methods, loop
conditions, or variants. Specifications still have their distinct historical
`pre(reference)` operator.

For a node with observers, the frontend makes every missing state fallback
explicit before observer instrumentation and later transition normalization.
The generated self-loop then receives the same observer updates and delay-cell
commits as a written transition, so observers advance even when no source
transition guard matches. The initial state is deliberately excluded from this
completion: it must already have an unguarded transition or one explicitly
guarded by `true`, and the frontend rejects the node instead of generating an
`init -> init` fallback.

Observer scheduling also follows free references captured by called local
predicates, recursively through nested predicate calls. A dependency hidden in
a predicate body therefore orders observer updates exactly like a direct
reference; an induced instantaneous cycle is rejected.

A boolean expression is itself a formula: `true`, `false`, a boolean variable,
`pre(flag)`, a boolean predicate call, and a boolean pure-function call do not
need to be written as `... = true`. The frontend accepts the general expression
syntax first, then rejects non-boolean formulas during typing.

## Specification definitions

Repeated temporal schemes can be named with local `spec def` declarations:

```kairos
spec def responds_next(trigger: Formula, response: Formula) =
  G($trigger => X($response));

node controller(trigger: bool) returns (response: bool)
contracts
  guarantee: responds_next([trigger], [response]);
// ...
```

These definitions are expanded before elaboration. They introduce neither
node composition nor a modular proof boundary.

`init:` is an initialization pseudo-source, not a control state. It therefore
cannot receive an invariant and is not selected by `in states`. The frontend
lowers it to a private state for the existing execution and proof engines.
Node guarantees are interpreted from the first real state; the corresponding
initial `X` is inserted during lowering rather than written in contracts.

## Where test examples are located

- Expected **valid** examples: `tests/ok/`
- Expected **invalid** examples: `tests/ko/`
