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

open Ast

module Pass :
  Pass_intf.S
    with type ast_in = Stage_types.parsed
     and type ast_out = Stage_types.parsed
     and type stage_in = unit
     and type stage_out = Automata_generation.node_builds
     and type info = Stage_info.automata_info = struct
  type ast_in = Stage_types.parsed
  type ast_out = Stage_types.parsed
  type stage_in = unit
  type stage_out = Automata_generation.node_builds
  type info = Stage_info.automata_info

  let run_with_info (p : ast_in) () : ast_out * stage_out * info =
    let state_count = ref 0 in
    let edge_count = ref 0 in
    let warnings = ref [] in
    let automata =
      List.map
        (fun n ->
          let build = Automata_generation.build_for_node n in
          let automaton = build.guarantee_automaton in
          state_count := !state_count + List.length automaton.states;
          edge_count := !edge_count + List.length automaton.grouped;
          (n.semantics.sem_nname, build))
        p
    in
    let info =
      {
        Stage_info.residual_state_count = !state_count;
        Stage_info.residual_edge_count = !edge_count;
        Stage_info.warnings = List.rev !warnings;
      }
    in
    (p, automata, info)

  let run (p : ast_in) () : ast_out * stage_out =
    let ast, stage, _info = run_with_info p () in
    (ast, stage)
end
