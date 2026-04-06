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
open Fo_specs

let of_ast_summary_formula ?origin (f : Ast.ltl_o) : Ir.summary_formula =
  {
    logic = fo_formula_of_non_temporal_ltl_exn f.value;
    meta = { origin; oid = f.oid; loc = f.loc };
  }

let of_ast_transition (t : Ast.transition) : Ir.transition =
  {
    src_state = t.src;
    dst_state = t.dst;
    guard_iexpr = t.guard;
    body_stmts = t.body;
  }

let of_ast_node (n : Ast.node) : Ir.node_ir =
  let semantics = Ast.semantics_of_node n in
  let spec = Ast.specification_of_node n in
  {
    context =
      {
        semantics =
          {
            Ir.sem_nname = semantics.sem_nname;
            sem_inputs = semantics.sem_inputs;
            sem_outputs = semantics.sem_outputs;
            sem_locals = semantics.sem_locals;
            sem_states = semantics.sem_states;
            sem_init_state = semantics.sem_init_state;
          };
        pre_k_map = [];
        source_info =
          {
            assumes = spec.spec_assumes;
            guarantees = spec.spec_guarantees;
            user_invariants = [];
            state_invariants = spec.spec_invariants_state_rel;
          };
      };
    summaries = [];
    init_invariant_goals = [];
  }

let of_ast_program (p : Ast.program) : Ir.node_ir list = List.map of_ast_node p
