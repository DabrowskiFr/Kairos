# Rocq Model (Automata-Only, Oracle-Conditional)

File:
- `KairosOracle.v`

Current status:
- explicit program automaton (`ProgramAutomaton`) and deterministic step selection (`prog_select`),
- explicit safety automata edges with FO labels (`label_e : Obs -> Prop`) and deterministic edge selection (`select_A`, `select_G`),
- explicit product model (`ProductState`, `ProductStep`, `product_step_wf`),
- obligations as Rocq predicates (`Obligation := StepCtx -> Prop`),
- relational generation (`GeneratedBy`) tied directly to well-formed product steps,
- local contradiction encoded by generated obligation semantics (`prod_obligation ps := ~ ctx_matches_ps _ ps`),
- proved lemmas:
  - `realizable_product_step`,
  - `realized_step_target_correct`,
  - `bad_local_step_if_G_violated`,
  - `generation_coverage`,
  - `no_bad_A_invariant`, `no_bad_G_invariant`,
- final theorem:
  - `oracle_conditional_correctness :
     forall u, avoids_bad_A u -> avoids_bad_G (run_trace u)`.

Remaining external assumptions:
- `prog_select_enabled`,
- `select_A_src`, `select_A_label`,
- `select_G_src`, `select_G_label`,
- `A_init_not_bad`, `G_init_not_bad`,
- oracle assumptions:
  - `Oracle_sound`,
  - `Oracle_complete`.
