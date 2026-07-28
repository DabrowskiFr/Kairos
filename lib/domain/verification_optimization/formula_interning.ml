(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

open Core_syntax

type strategy =
  | Preserve_allocations
  | Intern_location_free

let rec has_no_location : type phase. phase hexpr -> bool =
 fun formula ->
  formula.loc = None
  &&
  match formula.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ ->
      true
  | HPred (_, arguments) | HFunCall (_, arguments) ->
      List.for_all has_no_location arguments
  | HBin (_, left, right) | HCmp (_, left, right) ->
      has_no_location left && has_no_location right
  | HUn (_, inner) -> has_no_location inner

let intern_node
    (node : Core_syntax.history_free Ir.node_ir) :
    Core_syntax.history_free Ir.node_ir =
  let pool = Formula_canonical.create_pool () in
  let intern logic =
    if has_no_location logic then
      Formula_canonical.intern pool logic
    else logic
  in
  let intern_formula
      (formula : Core_syntax.history_free Ir.summary_formula) =
    { formula with logic = intern formula.logic }
  in
  let summaries =
    node.summaries
    |> List.map
         (fun
           (summary :
             Core_syntax.history_free Ir.product_step_summary)
         ->
           {
             summary with
             identity =
               {
                 summary.identity with
                 assume_guard =
                   intern summary.identity.assume_guard;
               };
             propagation_requires =
               List.map intern_formula
                 summary.propagation_requires;
             requires = List.map intern_formula summary.requires;
             ensures = List.map intern_formula summary.ensures;
             elaboration_checks =
               List.map intern_formula
                 summary.elaboration_checks;
             safe_cases =
               List.map
                 (fun
                   (case :
                     Core_syntax.history_free
                     Ir.safe_product_case)
                 ->
                   {
                     case with
                     admissible_guard =
                       intern_formula case.admissible_guard;
                   })
                 summary.safe_cases;
             unsafe_cases =
               List.map
                 (fun
                   (case :
                     Core_syntax.history_free
                     Ir.unsafe_product_case)
                 ->
                   {
                     case with
                     excluded_guard =
                       intern_formula case.excluded_guard;
                   })
                 summary.unsafe_cases;
           })
  in
  {
    node with
    summaries;
    init_invariant_goals =
      List.map intern_formula node.init_invariant_goals;
  }

let apply_node ~(strategy : strategy) node =
  match strategy with
  | Preserve_allocations -> node
  | Intern_location_free -> intern_node node

let apply_program ~(strategy : strategy) (program : Ir.program_ir) =
  match strategy with
  | Preserve_allocations -> program
  | Intern_location_free ->
      { Ir.nodes = List.map (apply_node ~strategy) program.nodes }
