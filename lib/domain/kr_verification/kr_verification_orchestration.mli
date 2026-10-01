(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Domain orchestration for verification IR construction.

    The reference-product entry point is the correction-critical boundary from
    an elaborated program plus supplied automata to product summaries. Runtime
    options, external prover calls, dumps, profiling, and backend grouping must
    stay outside this boundary. *)

open Kr_verification_automata_types

(** Input of the reference product construction. *)
type reference_product_input = {
  proof_case_program : Kr_verification_cases.t;
  automata : (Kr_domain_core_syntax.ident * automata_spec) list;
  reachability_strategy : Kr_verification_reachability.strategy;
}

(** One node produced by the canonical product construction, with the
    core-owned proof case from which its product analysis and IR originate. *)
type product_node = private {
  proof_case : Kr_verification_cases.proof_case;
  analysis : Kr_verification_temporal_automata.node_data;
  reachability : Kr_verification_reachability.t;
  ir : Kr_domain_core_syntax.historical Kr_verification_ir.node_ir;
}

type instrumented_product_node = private {
  proof_case : Kr_verification_cases.proof_case;
  ir : Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir;
}
(** A lowered IR node whose association with its core proof case has survived
    every instrumentation pass and been structurally checked after each one. *)

type reference_product = private {
  nodes : product_node list;
}

(** Instrumentation passes currently run after product summaries exist. *)
type instrumented_ir_pass =
  | Pre_pass
  | Post_pass
  | Temporal_lower_pass

type pass_observer = {
  before_historical :
    instrumented_ir_pass ->
    Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list ->
    unit;
  after_historical :
    instrumented_ir_pass ->
    Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list ->
    unit;
  before_lowering :
    instrumented_ir_pass ->
    Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list ->
    unit;
  after_lowering :
    instrumented_ir_pass ->
    Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir list ->
    unit;
}

(** Build the named reference product from an elaborated program and supplied
    automata. *)
val build_reference_product :
  reference_product_input ->
  (reference_product, string) result

(** Run the instrumentation-oriented IR passes over product summaries.
    [body_effect_summaries] defaults to [false] and controls only optional
    symbolic body effects, not temporal facts or their preservation. *)
val build_instrumented_ir :
  ?observe_fact_family:(Kr_verification_fact_metrics.snapshot -> unit) ->
  ?pass_observer:pass_observer ->
  ?body_effect_summaries:bool ->
  reference_product ->
  (instrumented_product_node list, string) result
