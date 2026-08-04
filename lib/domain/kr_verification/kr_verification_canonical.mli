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
  proof_cases : Kr_verification_cases.t;
  reference_product : Kr_verification_orchestration.reference_product;
  instrumented_nodes : Kr_verification_orchestration.instrumented_product_node list;
  obligations : Kr_verification_obligations.t list;
}

val build :
  ?observe_fact_family:(Kr_verification_fact_metrics.snapshot -> unit) ->
  ?pass_observer:Kr_verification_orchestration.pass_observer ->
  ?observe_stage:(stage -> unit) ->
  reachability_strategy:Kr_verification_reachability.strategy ->
  proof_cases:Kr_verification_cases.t ->
  automata:
    (Kr_domain_core_syntax.ident * Kr_verification_automata_types.automata_spec) list ->
  unit ->
  (t, string) result
(** Builds the reference product, runs the typed enrichment/lowering passes,
    and projects their result to canonical individual obligations. *)
