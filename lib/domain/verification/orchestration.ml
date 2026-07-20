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

(** Orchestration entrypoint for domain IR construction.

    The reference-product entry point names the correction-critical path from
    an elaborated program plus supplied automata to product summaries. The
    instrumentation passes remain separate: they are useful for proof/backend
    construction, but they must not be confused with external tool choices,
    dumps, profiling, or backend-specific grouping. *)

open Automaton_types

(** Helper value. *)

let ( let* ) = Result.bind

(** Type [reference_product_input]. *)

type reference_product_input = {
  reference_program : Verification_model.program_model;
  reference_automata : (Core_syntax.ident * automata_spec) list;
}

(** Type [reference_product]. *)

type reference_product = {
  reference_nodes : Ir.node_ir list;
}

(** Type [instrumented_ir_pass]. *)

type instrumented_ir_pass =
  | Pre_pass
  | Product_reachability_pass
  | Post_pass
  | Temporal_lower_pass
  | Formula_sharing_pass

(** The proof export is taken before temporal lowering; the backend keeps the
    fully lowered program. *)
type instrumented_ir = {
  proof_nodes : Ir.node_ir list;
  backend_program : Ir.program_ir;
}

(** [build_reference_product] helper value. *)

let build_reference_product
    ({ reference_program; reference_automata } : reference_product_input) :
    (reference_product, string) result =
  let* reference_nodes =
    From_model.of_model_program ~automata:reference_automata reference_program
  in
  Ok { reference_nodes }

(** [build_instrumented_ir] helper value. *)

let build_instrumented_ir
    ?observe_fact_family
    ?(run_pass = fun _ pass nodes -> pass nodes)
    (initial_nodes : Ir.node_ir list) :
    instrumented_ir =
  let pre_nodes =
    initial_nodes
    |> run_pass Pre_pass (Pre.run_program ?observe_family:observe_fact_family)
    |> run_pass Product_reachability_pass Product_reachability.run_program
    |> run_pass Post_pass (Post.run_program ?observe_family:observe_fact_family)
  in
  let backend_nodes =
    pre_nodes
    |> run_pass Temporal_lower_pass Temporal_lower.run_program
    |> run_pass Formula_sharing_pass Formula_sharing.run_program
  in
  {
    proof_nodes = pre_nodes;
    backend_program = ({ nodes = backend_nodes } : Ir.program_ir);
  }
