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
  reference_program : Verification_model.program_model;
  reference_automata : (Core_syntax.ident * automata_spec) list;
}

(** Output of the reference product construction. *)
type reference_product = {
  reference_nodes : Ir.node_ir list;
}

(** Instrumentation passes currently run after product summaries exist. *)
type instrumented_ir_pass =
  | Pre_pass
  | Product_reachability_pass
  | Post_pass
  | Temporal_lower_pass
  | Formula_sharing_pass

type instrumented_ir = {
  proof_nodes : Ir.node_ir list;
  backend_program : Ir.program_ir;
}

(** Build the named reference product from an elaborated program and supplied
    automata. *)
val build_reference_product :
  reference_product_input ->
  (reference_product, string) result

(** Run the instrumentation-oriented IR passes over product summaries. *)
val build_instrumented_ir :
  ?observe_fact_family:(Ir_fact_family_metrics.snapshot -> unit) ->
  ?run_pass:
    (instrumented_ir_pass ->
     (Ir.node_ir list -> Ir.node_ir list) ->
     Ir.node_ir list ->
     Ir.node_ir list) ->
  Ir.node_ir list ->
  instrumented_ir
