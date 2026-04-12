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

(** Automata-generation pass implementation.

    This pass computes require/ensures automata builds for each parsed node and
    reports aggregate residual-state/edge metrics. *)

open Ast

type automata_info = {
  residual_state_count : int;
  residual_edge_count : int;
  warnings : string list;
}

type build_automaton =
  atom_map:((Core_syntax.hexpr * Core_syntax.relop * Core_syntax.hexpr) * Core_syntax.ident) list ->
  atom_names:Core_syntax.ident list ->
  atom_named_exprs:(Core_syntax.ident * Core_syntax.expr) list ->
  Core_syntax.ltl ->
  Automata_generation.automata_automaton

let run_with_info (p : Ast.program) (build_automaton : build_automaton) :
    Ast.program * Automata_generation.node_builds * automata_info =
  let state_count = ref 0 in
  let edge_count = ref 0 in
  let warnings = ref [] in
  let automata =
    List.map
      (fun n ->
        let build = Automata_generation.build_for_node ~build_automaton n in
        let automaton = build.guarantee_automaton in
        state_count := !state_count + List.length automaton.states;
        edge_count := !edge_count + List.length automaton.grouped;
        (n.semantics.sem_nname, build))
      p
  in
  let info =
    {
      residual_state_count = !state_count;
      residual_edge_count = !edge_count;
      warnings = List.rev !warnings;
    }
  in
  (p, automata, info)

let run (p : Ast.program) (build_automaton : build_automaton) :
    Ast.program * Automata_generation.node_builds =
  let ast, stage, _info = run_with_info p build_automaton in
  (ast, stage)
