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

(** Physical sharing for repeated canonical IR formulas.

    This pass does not simplify or rewrite formulas logically. It only replaces
    structurally equal top-level formula payloads by one representative value so
    later backend stages can benefit from cheaper physical-equality fast paths
    when comparing or deduplicating repeated large formulas. *)

module Abs = Ir

type table = Core_syntax.history_free Formula_canonical.pool

let share_hexpr (table : table)
    (formula : Core_syntax.history_free Core_syntax.hexpr) :
    Core_syntax.history_free Core_syntax.hexpr =
  match formula.loc with
  | Some _ -> formula
  | None -> Formula_canonical.intern table formula

let share_summary_formula table
    (formula : Core_syntax.history_free Abs.summary_formula) :
    Core_syntax.history_free Abs.summary_formula =
  { formula with logic = share_hexpr table formula.logic }

let share_safe_case table
    (case : Core_syntax.history_free Abs.safe_product_case) :
    Core_syntax.history_free Abs.safe_product_case =
  {
    case with
    admissible_guard = share_summary_formula table case.admissible_guard;
  }

let share_unsafe_case table
    (case : Core_syntax.history_free Abs.unsafe_product_case) :
    Core_syntax.history_free Abs.unsafe_product_case =
  {
    case with
    excluded_guard = share_summary_formula table case.excluded_guard;
  }

let share_summary table
    (summary : Core_syntax.history_free Abs.product_step_summary) :
    Core_syntax.history_free Abs.product_step_summary =
  {
    summary with
    identity =
      {
        summary.identity with
        assume_guard = share_hexpr table summary.identity.assume_guard;
      };
    propagation_requires =
      List.map (share_summary_formula table) summary.propagation_requires;
    requires = List.map (share_summary_formula table) summary.requires;
    ensures = List.map (share_summary_formula table) summary.ensures;
    elaboration_checks =
      List.map (share_summary_formula table) summary.elaboration_checks;
    safe_cases = List.map (share_safe_case table) summary.safe_cases;
    unsafe_cases = List.map (share_unsafe_case table) summary.unsafe_cases;
  }

let run_node (node : Core_syntax.history_free Abs.node_ir) :
    Core_syntax.history_free Abs.node_ir =
  let table = Formula_canonical.create_pool () in
  {
    node with
    summaries = List.map (share_summary table) node.summaries;
    init_invariant_goals =
      List.map (share_summary_formula table) node.init_invariant_goals;
  }

let run_program (program : Core_syntax.history_free Abs.node_ir list) :
    Core_syntax.history_free Abs.node_ir list =
  List.map run_node program
