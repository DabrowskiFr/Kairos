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

open Automaton_types

(** Input of the reference product construction. *)
type reference_product_input = {
  proof_case_program : Proof_case_program.t;
  automata : (Core_syntax.ident * automata_spec) list;
}

(** One node produced by the canonical product construction, with the
    core-owned proof case from which its product analysis and IR originate. *)
type product_node = private {
  proof_case : Proof_case_program.proof_case;
  analysis : Temporal_automata.node_data;
  ir : Core_syntax.historical Ir.node_ir;
}

type instrumented_product_node = private {
  proof_case : Proof_case_program.proof_case;
  ir : Core_syntax.history_free Ir.node_ir;
}
(** A lowered IR node whose association with its core proof case has survived
    every instrumentation pass and been structurally checked after each one. *)

val map_instrumented_product_node :
  (Core_syntax.history_free Ir.node_ir ->
  Core_syntax.history_free Ir.node_ir) ->
  instrumented_product_node ->
  (instrumented_product_node, string) result
(** Applies a structure-preserving transformation without releasing ownership
    of the proof-case/IR association. The result must be structurally equal to
    the input (physical representation may differ), and its provenance is
    checked again. *)

type reference_product = private {
  nodes : product_node list;
}

(** Instrumentation passes currently run after product summaries exist. *)
type instrumented_ir_pass =
  | Pre_pass
  | Product_reachability_pass
  | Post_pass
  | Temporal_lower_pass

type pass_observer = {
  before_historical :
    instrumented_ir_pass ->
    Core_syntax.historical Ir.node_ir list ->
    unit;
  after_historical :
    instrumented_ir_pass ->
    Core_syntax.historical Ir.node_ir list ->
    unit;
  before_lowering :
    instrumented_ir_pass ->
    Core_syntax.historical Ir.node_ir list ->
    unit;
  after_lowering :
    instrumented_ir_pass ->
    Core_syntax.history_free Ir.node_ir list ->
    unit;
}

(** Build the named reference product from an elaborated program and supplied
    automata. *)
val build_reference_product :
  reference_product_input ->
  (reference_product, string) result

(** Run the instrumentation-oriented IR passes over product summaries. *)
val build_instrumented_ir :
  ?observe_fact_family:(Ir_fact_family_metrics.snapshot -> unit) ->
  ?pass_observer:pass_observer ->
  reference_product ->
  (instrumented_product_node list, string) result
