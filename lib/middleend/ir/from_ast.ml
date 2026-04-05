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

let of_ast_contract_formula ?origin (f : Ast.ltl_o) : Ir.contract_formula =
  {
    logic = fo_formula_of_non_temporal_ltl_exn f.value;
    meta = { origin; oid = f.oid; loc = f.loc };
  }

let of_ast_transition (t : Ast.transition) : Ir.transition =
  {
    src = t.src;
    dst = t.dst;
    guard = t.guard;
    body = t.body;
  }

let of_ast_node (n : Ast.node) : Ir.node =
  let semantics = Ast.semantics_of_node n in
  let spec = Ast.specification_of_node n in
  {
    semantics;
    trans = List.map of_ast_transition n.semantics.sem_trans;
    product_transitions = [];
    source_info =
      {
        assumes = spec.spec_assumes;
        guarantees = spec.spec_guarantees;
        user_invariants = [];
        state_invariants = spec.spec_invariants_state_rel;
      };
    coherency_goals = [];
    proof_views = Ir.empty_proof_views;
  }

let of_ast_program (p : Ast.program) : Ir.node list = List.map of_ast_node p
