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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

type step_contract = {
  transition_id : string;
  program_step : Ir.transition;
  product_src : Ir.product_state;
  assume_guard : Core_syntax.history_free Ir.summary_formula;
  requires : Core_syntax.history_free Ir.summary_formula list;
  ensures : Core_syntax.history_free Ir.summary_formula list;
  elaboration_checks : Core_syntax.history_free Ir.summary_formula list;
}

let preconditions (contract : step_contract) =
  contract.requires @ [ contract.assume_guard ]

let postconditions (contract : step_contract) =
  contract.ensures @ contract.elaboration_checks

let common_requires
    (summary : Core_syntax.history_free Ir.product_step_summary) =
  summary.propagation_requires @ summary.requires

let transition_id_of_summary
    (summary : Core_syntax.history_free Ir.product_step_summary) =
  Printf.sprintf "tr_%d" summary.trace.step_uid

let contract_of_summary
    (summary : Core_syntax.history_free Ir.product_step_summary) =
  {
    transition_id = transition_id_of_summary summary;
    program_step = summary.identity.program_step;
    product_src = summary.identity.product_src;
    assume_guard = Ir_formula.make summary.identity.assume_guard;
    requires = common_requires summary;
    ensures = summary.ensures;
    elaboration_checks = summary.elaboration_checks;
  }

let of_ir_node (node : Core_syntax.history_free Ir.node_ir) :
    step_contract list =
  node.summaries
  |> List.map contract_of_summary
