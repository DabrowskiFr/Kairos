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

open Core_syntax

type product_state_anchor = Ir.product_state

type product_step_anchor = {
  product_src : product_state_anchor;
  product_dst : product_state_anchor;
  program_transition_id : int;
}

type 'phase summary_identity = {
  program_transition_id : int;
  program_step : Ir.transition;
  product_src : product_state_anchor;
  assume_guard : 'phase hexpr;
}

type 'phase summary = {
  identity : 'phase summary_identity;
  propagation_requires : 'phase Ir.summary_formula list;
  requires : 'phase Ir.summary_formula list;
  runtime_requires : 'phase Ir.summary_formula list;
  ensures : 'phase Ir.summary_formula list;
  elaboration_checks : 'phase Ir.summary_formula list;
  safe_cases : 'phase Ir.safe_product_case list;
  unsafe_cases : 'phase Ir.unsafe_product_case list;
  source_summary : 'phase Ir.product_step_summary;
}

type 'phase t = { summaries : 'phase summary list }

let same_product_state (a : product_state_anchor) (b : product_state_anchor) =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let of_ir_summary ~runtime_requires_of_summary
    (source_summary : 'phase Ir.product_step_summary) : 'phase summary =
  let source_identity = source_summary.identity in
  {
    identity =
      {
        program_transition_id = source_summary.trace.step_uid;
        program_step = source_identity.program_step;
        product_src = source_identity.product_src;
        assume_guard = source_identity.assume_guard;
      };
    propagation_requires = source_summary.propagation_requires;
    requires = source_summary.requires;
    runtime_requires = runtime_requires_of_summary source_summary;
    ensures = source_summary.ensures;
    elaboration_checks = source_summary.elaboration_checks;
    safe_cases = source_summary.safe_cases;
    unsafe_cases = source_summary.unsafe_cases;
    source_summary;
  }

let of_ir_node ?(runtime_requires_of_summary = fun _ -> [])
    (node : 'phase Ir.node_ir) : 'phase t =
  {
    summaries =
      List.map (of_ir_summary ~runtime_requires_of_summary) node.summaries;
  }

let find_by_identity (projection : 'phase t) ~program_transition_id ~product_src
    ~assume_guard =
  let assume_guard = Formula_canonical.key assume_guard in
  List.find_opt
    (fun (summary : 'phase summary) ->
      summary.identity.program_transition_id = program_transition_id
      && same_product_state summary.identity.product_src product_src
      && Formula_canonical.key summary.identity.assume_guard = assume_guard)
    projection.summaries
