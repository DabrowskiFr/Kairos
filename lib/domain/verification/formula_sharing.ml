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

type table = (string, Core_syntax.hexpr list) Hashtbl.t

let share_hexpr (table : table) (formula : Core_syntax.hexpr) :
    Core_syntax.hexpr =
  match formula.loc with
  | Some _ -> formula
  | None -> (
      let key = Core_fo_simplifier.key_of_hexpr formula in
      match Hashtbl.find_opt table key with
      | Some representatives -> (
          match List.find_opt (( = ) formula) representatives with
          | Some representative -> representative
          | None ->
              Hashtbl.replace table key (formula :: representatives);
              formula)
      | None ->
          Hashtbl.add table key [ formula ];
          formula)

let share_summary_formula table (formula : Abs.summary_formula) :
    Abs.summary_formula =
  { formula with logic = share_hexpr table formula.logic }

let share_state_invariant table (invariant : Abs.state_invariant) :
    Abs.state_invariant =
  { invariant with formula = share_hexpr table invariant.formula }

let share_safe_case table (case : Abs.safe_product_case) :
    Abs.safe_product_case =
  {
    case with
    admissible_guard = share_summary_formula table case.admissible_guard;
  }

let share_unsafe_case table (case : Abs.unsafe_product_case) :
    Abs.unsafe_product_case =
  {
    case with
    excluded_guard = share_summary_formula table case.excluded_guard;
  }

let share_summary table (summary : Abs.product_step_summary) :
    Abs.product_step_summary =
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
    safe_cases = List.map (share_safe_case table) summary.safe_cases;
    unsafe_cases = List.map (share_unsafe_case table) summary.unsafe_cases;
  }

let run_node (node : Abs.node_ir) : Abs.node_ir =
  let table = Hashtbl.create 512 in
  {
    node with
    source_info =
      {
        node.source_info with
        state_invariants =
          List.map (share_state_invariant table)
            node.source_info.state_invariants;
      };
    summaries = List.map (share_summary table) node.summaries;
    init_invariant_goals =
      List.map (share_summary_formula table) node.init_invariant_goals;
  }

let run_program (program : Abs.node_ir list) : Abs.node_ir list =
  List.map run_node program
