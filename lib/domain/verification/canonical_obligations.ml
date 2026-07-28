(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

type stage1 = {
  product_summaries :
    Core_syntax.historical Product_summary_projection.t;
  clauses : Kernel_clause_projection.classified_clause list;
}

let build_stage1 ~(node : Core_syntax.historical Ir.node_ir)
    ~(initial_state : Kernel_clause_projection.product_state_anchor)
    ~(steps : Kernel_clause_projection.product_step list) ~is_live_state :
    stage1 =
  {
    product_summaries = Product_summary_projection.of_ir_node node;
    clauses =
      Kernel_clause_projection.build ~node ~initial_state ~steps ~is_live_state;
  }
