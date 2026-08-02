(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Canonical backend-neutral verification construction.

    This is the scientific boundary from a core-owned proof-case program and
    its supplied automata to individual canonical obligations. It owns product
    construction, historical enrichment, temporal lowering, and obligation
    projection. It performs no proof optimization or backend translation. *)

type stage =
  | Reference_product_built
  | Instrumented_ir_built
(** Observable boundaries of the canonical construction. Observation cannot
    alter a stage result. *)

type t = private {
  proof_cases : Proof_case_program.t;
  reference_product : Orchestration.reference_product;
  instrumented_nodes : Orchestration.instrumented_product_node list;
  obligations : Verification_obligations.t list;
}

val build :
  ?observe_fact_family:(Ir_fact_family_metrics.snapshot -> unit) ->
  ?pass_observer:Orchestration.pass_observer ->
  ?observe_stage:(stage -> unit) ->
  reachability_strategy:Product_reachability.strategy ->
  proof_cases:Proof_case_program.t ->
  automata:
    (Core_syntax.ident * Automaton_types.automata_spec) list ->
  unit ->
  (t, string) result
(** Builds the reference product, runs the typed enrichment/lowering passes,
    and projects their result to canonical individual obligations. *)
