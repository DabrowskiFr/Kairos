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

(** {2 Main pass} *)

let eliminate (annotated : Ir_proof_views.annotated_node) : Ir_proof_views.verified_node =
  let raw = annotated.raw in
  let transitions =
    List.map
      (fun (t : Ir_proof_views.annotated_transition) ->
        ({
          Ir_proof_views.core = t.raw.core;
          guard = t.raw.guard;
          clauses = t.clauses;
        } : Ir_proof_views.verified_transition))
      annotated.transitions
  in
  {
    Ir_proof_views.core = raw.core;
    transitions;
    product_transitions = [];
    assumes = raw.assumes;
    guarantees = raw.guarantees;
    init_invariant_goals = annotated.init_invariant_goals;
    user_invariants = annotated.user_invariants;
  }

let apply_node (node : Ir.node_ir) : Ir.node_ir = node

let apply_program (program : Ir.node_ir list) : Ir.node_ir list = List.map apply_node program
