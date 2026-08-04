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
  program_step : Kr_verification_ir.transition;
  monitor_source : Kr_verification_ir.monitor_state_pair;
  assume_guard : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula;
  requires : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list;
  ensures : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list;
  elaboration_checks : Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list;
}

let product_source (contract : step_contract) : Kr_verification_ir.product_state =
  {
    prog_state = contract.program_step.src_state;
    assume_state_index = contract.monitor_source.assume_state_index;
    guarantee_state_index =
      contract.monitor_source.guarantee_state_index;
  }

let preconditions (contract : step_contract) =
  contract.requires @ [ contract.assume_guard ]

let postconditions (contract : step_contract) =
  contract.ensures @ contract.elaboration_checks

let common_requires
    (summary : Kr_domain_core_syntax.history_free Kr_verification_ir.product_step_summary) =
  summary.propagation_requires @ summary.requires

let transition_id_of_summary
    (summary : Kr_domain_core_syntax.history_free Kr_verification_ir.product_step_summary) =
  Printf.sprintf "tr_%d" summary.trace.step_uid

let contract_of_summary
    (summary : Kr_domain_core_syntax.history_free Kr_verification_ir.product_step_summary) =
  {
    transition_id = transition_id_of_summary summary;
    program_step = summary.identity.program_step;
    monitor_source = summary.identity.monitor_source;
    assume_guard = Ir_formula.make summary.identity.assume_guard;
    requires = common_requires summary;
    ensures = summary.ensures;
    elaboration_checks = summary.elaboration_checks;
  }

let of_ir_node (node : Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir) :
    step_contract list =
  node.summaries
  |> List.map contract_of_summary
