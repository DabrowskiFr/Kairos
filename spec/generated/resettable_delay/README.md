# resettable_delay walkthrough

This directory contains concrete artifacts generated from
`tests/ok/inputs/resettable_delay.kairos`.

Source example:
- `/Users/fredericdabrowski/Repos/kairos/tests/ok/inputs/resettable_delay.kairos`

Generated with the V2 CLI only:

```bash
opam exec --switch=5.4.1+options -- \
  _build/default/bin/cli/main_v2.exe \
  --dump-automata=/Users/fredericdabrowski/Repos/kairos/spec/generated/resettable_delay/automata.txt \
  /Users/fredericdabrowski/Repos/kairos/tests/ok/inputs/resettable_delay.kairos

opam exec --switch=5.4.1+options -- \
  _build/default/bin/cli/main_v2.exe \
  --dump-product=/Users/fredericdabrowski/Repos/kairos/spec/generated/resettable_delay/product.txt \
  /Users/fredericdabrowski/Repos/kairos/tests/ok/inputs/resettable_delay.kairos

opam exec --switch=5.4.1+options -- \
  _build/default/bin/cli/main_v2.exe \
  --dump-obligations-map=/Users/fredericdabrowski/Repos/kairos/spec/generated/resettable_delay/obligations.txt \
  /Users/fredericdabrowski/Repos/kairos/tests/ok/inputs/resettable_delay.kairos

opam exec --switch=5.4.1+options -- \
  _build/default/bin/cli/main_v2.exe \
  --dump-obc=/Users/fredericdabrowski/Repos/kairos/spec/generated/resettable_delay/resettable_delay.obc+ \
  --dump-obc-abstract \
  /Users/fredericdabrowski/Repos/kairos/tests/ok/inputs/resettable_delay.kairos

opam exec --switch=5.4.1+options -- \
  _build/default/bin/cli/main_v2.exe \
  --dump-why=/Users/fredericdabrowski/Repos/kairos/spec/generated/resettable_delay/resettable_delay.mlw \
  /Users/fredericdabrowski/Repos/kairos/tests/ok/inputs/resettable_delay.kairos

opam exec --switch=5.4.1+options -- \
  _build/default/bin/cli/main_v2.exe \
  --dump-why3-vc=/Users/fredericdabrowski/Repos/kairos/spec/generated/resettable_delay/resettable_delay_vc.txt \
  /Users/fredericdabrowski/Repos/kairos/tests/ok/inputs/resettable_delay.kairos
```

Summary of the current outputs:
- assumption residual states: `A0`, `A1`
- guarantee residual states: `G0`, `G1`, `G2`
- reachable product states: `5`
- generated clauses: `22`
  - safety: `3`
  - coherence: `19`
  - init goals: `1`
  - propagation: `18`
  - user invariant: `6`
  - automaton support: `12`

Current proof-backend status:
- extraction succeeds end-to-end;
- the generated Why3 obligations are discharged with Z3 using Why3
  transformations:

```bash
tmpconf=$(mktemp /tmp/why3conf.XXXXXX)
opam exec --switch=5.4.1+options -- why3 config --config "$tmpconf" detect
opam exec --switch=5.4.1+options -- why3 -C "$tmpconf" prove \
  -a simplify_formula \
  -a eliminate_if_term \
  -a remove_unused \
  -a split_vc \
  -P z3 \
  -t 30 \
  /Users/fredericdabrowski/Repos/kairos/spec/generated/resettable_delay/resettable_delay.mlw
```

- with this command, Why3 exits successfully on the example (`EXIT=0`).

The generated Why3 file now contains an explicit initial automaton-support goal:

```why3
goal coherency_goal_1:
  forall vars : vars, reset : int, x : int.
    ((vars.st = Init) /\ (vars.__aut_state = Aut0)) ->
    true ->
    (vars.__aut_state = Aut0)
```

This is the sound backend counterpart of the Rocq `InitialGoal` for automaton
support. The previous unsound shape `forall vars. __aut_state = Aut0` is no
longer emitted.
