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

open Ast

(** Helper value. *)

let ( let* ) = Result.bind

(** Type [run_artifacts]. *)

type run_artifacts = {
  summaries_nodes : Ir.node_ir list;
  instrumentation_program : Ir.program_ir;
}

(** [build_initial_ir] helper value. *)

let build_initial_ir ~(automata : Automata_generation.node_builds) (parsed : Ast.program) :
    (Ir.node_ir list, string) result =
  From_ast.of_ast_program ~automata parsed

(** [build_instrumented_ir] helper value. *)

let build_instrumented_ir (initial_nodes : Ir.node_ir list) : Ir.program_ir =
  let nodes =
    initial_nodes
    |> Pre.run_program
    |> Post.run_program
    |> Temporal_lower.run_program
  in
  ({ nodes } : Ir.program_ir)

(** [run] helper value. *)

let run (parsed : Ast.program) (automata : Automata_generation.node_builds) :
    (run_artifacts, string) result =
  let* summaries_nodes = build_initial_ir ~automata parsed in
  let instrumentation_program = build_instrumented_ir summaries_nodes in
  Ok { summaries_nodes; instrumentation_program }
