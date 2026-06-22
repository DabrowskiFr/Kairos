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

(** Orchestration entrypoint for canonical IR construction.

    The module drives the IR pipeline from parsed AST + automata builds and
    returns both initial summaries and fully instrumented IR. *)

open Automaton_types

(** Helper value. *)

let ( let* ) = Result.bind

(** Type [run_artifacts]. *)

type run_artifacts = {
  summaries_nodes : Ir.node_ir list;
  instrumentation_program : Ir.program_ir;
}

(** Type [instrumented_ir_pass]. *)

type instrumented_ir_pass =
  | Pre_pass
  | Product_reachability_pass
  | Post_pass
  | Temporal_lower_pass
  | Formula_sharing_pass

(** [build_initial_ir] helper value. *)

let build_initial_ir
    ~(automata : (Core_syntax.ident * automata_spec) list)
    (program : Verification_model.program_model) :
    (Ir.node_ir list, string) result =
  From_model.of_model_program ~automata program

(** [build_instrumented_ir] helper value. *)

let build_instrumented_ir
    ?observe_fact_family
    ?(run_pass = fun _ pass nodes -> pass nodes)
    (initial_nodes : Ir.node_ir list) :
    Ir.program_ir =
  let nodes =
    initial_nodes
    |> run_pass Pre_pass (Pre.run_program ?observe_family:observe_fact_family)
    |> run_pass Product_reachability_pass Product_reachability.run_program
    |> run_pass Post_pass (Post.run_program ?observe_family:observe_fact_family)
    |> run_pass Temporal_lower_pass Temporal_lower.run_program
    |> run_pass Formula_sharing_pass Formula_sharing.run_program
  in
  ({ nodes } : Ir.program_ir)

(** [run] helper value. *)

let run
    (program : Verification_model.program_model)
    (automata : (Core_syntax.ident * automata_spec) list) :
    (run_artifacts, string) result =
  let* summaries_nodes = build_initial_ir ~automata program in
  let instrumentation_program = build_instrumented_ir summaries_nodes in
  Ok { summaries_nodes; instrumentation_program }
