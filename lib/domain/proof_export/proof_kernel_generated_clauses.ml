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

open Core_syntax

module Abs = Ir
module K = Kernel_clause_projection
open Proof_kernel_types

let build_generated_clauses ~(node : Core_syntax.historical Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    ~(initial_state : product_state_ir) ~(steps : product_step_ir list)
    ~automaton_guard_fo:_ ~is_live_state : generated_clause_ir list =
  let is_live_product_state st =
    is_live_state ~analysis
      (Proof_kernel_clause_context.product_state_to_product_types st)
  in
  let stage1 =
    Canonical_obligations.build_stage1 ~node
    ~initial_state:(Proof_kernel_clause_context.product_state_to_kernel initial_state)
    ~steps:(List.map Proof_kernel_clause_context.product_step_to_kernel steps)
    ~is_live_state:is_live_product_state
  in
  stage1.clauses
