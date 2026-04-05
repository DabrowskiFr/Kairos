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

module Abs = Ir

(** Lift an abstract transition into an annotated transition skeleton.
    Transition-level clauses are intentionally empty at this stage. *)
let annotate_transition (raw : Ir_proof_views.raw_transition) : Ir_proof_views.annotated_transition =
  { raw; clauses = { requires = []; ensures = [] } }

(** Annotate a raw node with transition-level proof payload. *)
let annotate ~(raw : Ir_proof_views.raw_node) ~(node : Abs.node_ir)
    : Ir_proof_views.annotated_node =
  let _ = node in
  let transitions = List.map annotate_transition raw.transitions in
  {
    raw;
    transitions;
    coherency_goals = node.goals;
    user_invariants = node.context.source_info.user_invariants;
  }
