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

let ( let* ) = Result.bind

let formula_meta_to_yojson (m : Ir.formula_meta) : Yojson.Safe.t =
  let option_to_yojson f = function None -> `Null | Some x -> f x in
  `Assoc
    [
      ("oid", `Int m.oid);
      ("loc", option_to_yojson Loc.loc_to_yojson m.loc);
      ("family", option_to_yojson (fun s -> `String s) m.family);
    ]

let formula_meta_of_yojson (json : Yojson.Safe.t) : (Ir.formula_meta, string) result =
  let option_of_yojson f = function `Null -> Ok None | x -> Result.map Option.some (f x) in
  match json with
  | `Assoc fields ->
      let find name = List.assoc_opt name fields in
      let* oid_json = Option.to_result ~none:"formula_meta: missing field 'oid'" (find "oid") in
      let* loc_json = Option.to_result ~none:"formula_meta: missing field 'loc'" (find "loc") in
      let* loc = option_of_yojson Loc.loc_of_yojson loc_json in
      let* family =
        match find "family" with
        | None -> Ok None
        | Some json -> option_of_yojson (function `String s -> Ok s | _ -> Error "formula_meta.family: expected string") json
      in
      let oid =
        match oid_json with
        | `Int n -> Ok n
        | _ -> Error "formula_meta.oid: expected int"
      in
      let* oid = oid in
      Ok { Ir.oid; loc; family }
  | _ -> Error "formula_meta: expected object"

let summary_formula_to_yojson (f : Core_syntax.historical Ir.summary_formula) : Yojson.Safe.t =
  `Assoc
    [
      ("logic", Core_syntax.hexpr_to_yojson f.logic);
      ("meta", formula_meta_to_yojson f.meta);
    ]

let summary_formula_of_yojson (json : Yojson.Safe.t) : (Core_syntax.historical Ir.summary_formula, string) result =
  match json with
  | `Assoc fields ->
      let find name =
        match List.assoc_opt name fields with
        | Some v -> Ok v
        | None -> Error (Printf.sprintf "summary_formula: missing field '%s'" name)
      in
      let* logic_json = find "logic" in
      let* meta_json = find "meta" in
      let* logic = Core_syntax.historical_hexpr_of_yojson logic_json in
      let* meta = formula_meta_of_yojson meta_json in
      Ok { Ir.logic; meta }
  | _ -> Error "summary_formula: expected object"

let summary_formula_list_to_yojson (xs : Core_syntax.historical Ir.summary_formula list) : Yojson.Safe.t =
  `List (List.map summary_formula_to_yojson xs)

let summary_formula_list_of_yojson (json : Yojson.Safe.t) :
    (Core_syntax.historical Ir.summary_formula list, string) result =
  match json with
  | `List items ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | x :: xs ->
            let* decoded = summary_formula_of_yojson x in
            go (decoded :: acc) xs
      in
      go [] items
  | _ -> Error "summary_formula list: expected list"

let clause_family_to_yojson
    (family : Obligation_family_projection.clause_family) : Yojson.Safe.t =
  `String (Obligation_family_projection.stable_name family)

let clause_family_of_yojson (json : Yojson.Safe.t) :
    (Obligation_family_projection.clause_family, string) result =
  match json with
  | `String raw -> (
      match Obligation_family_projection.of_stable_name raw with
      | Some family -> Ok family
      | None -> Error ("clause_family: unknown generated-obligation family " ^ raw))
  | _ -> Error "clause_family: expected string"

module K = Kernel_clause_projection

let field fields name =
  match List.assoc_opt name fields with
  | Some value -> Ok value
  | None -> Error (Printf.sprintf "missing field '%s'" name)

let string_field fields name =
  let* json = field fields name in
  match json with
  | `String value -> Ok value
  | _ -> Error (Printf.sprintf "%s: expected string" name)

let int_field fields name =
  let* json = field fields name in
  match json with
  | `Int value -> Ok value
  | _ -> Error (Printf.sprintf "%s: expected int" name)

let list_of_yojson item_of_yojson label = function
  | `List items ->
      let rec go acc = function
        | [] -> Ok (List.rev acc)
        | item :: rest ->
            let* decoded = item_of_yojson item in
            go (decoded :: acc) rest
      in
      go [] items
  | _ -> Error (label ^ ": expected list")

let time_tag_to_yojson = function
  | K.PreviousTick -> `String "previous_tick"
  | K.StepTickContext -> `String "step_tick_context"
  | K.CurrentTick -> `String "current_tick"

let time_tag_of_yojson = function
  | `String "previous_tick" -> Ok K.PreviousTick
  | `String "step_tick_context" -> Ok K.StepTickContext
  | `String "current_tick" -> Ok K.CurrentTick
  | `String raw -> Error ("time_tag: unknown tag " ^ raw)
  | _ -> Error "time_tag: expected string"

let product_state_anchor_to_yojson (st : K.product_state_anchor) : Yojson.Safe.t =
  `Assoc
    [
      ("prog_state", `String st.prog_state);
      ("assume_state_index", `Int st.assume_state_index);
      ("guarantee_state_index", `Int st.guarantee_state_index);
    ]

let product_state_anchor_of_yojson = function
  | `Assoc fields ->
      let* prog_state = string_field fields "prog_state" in
      let* assume_state_index = int_field fields "assume_state_index" in
      let* guarantee_state_index = int_field fields "guarantee_state_index" in
      Ok { Ir.prog_state; assume_state_index; guarantee_state_index }
  | _ -> Error "product_state_anchor: expected object"

let product_step_anchor_to_yojson (anchor : K.product_step_anchor) : Yojson.Safe.t =
  `Assoc
    [
      ("src", product_state_anchor_to_yojson anchor.K.psta_src);
      ("dst", product_state_anchor_to_yojson anchor.K.psta_dst);
      ("transition_id", `String anchor.K.psta_transition_id);
    ]

let product_step_anchor_of_yojson = function
  | `Assoc fields ->
      let* src_json = field fields "src" in
      let* dst_json = field fields "dst" in
      let* psta_src = product_state_anchor_of_yojson src_json in
      let* psta_dst = product_state_anchor_of_yojson dst_json in
      let* psta_transition_id = string_field fields "transition_id" in
      Ok { K.psta_src; psta_dst; psta_transition_id }
  | _ -> Error "product_step_anchor: expected object"

let product_step_class_to_yojson = function
  | K.StepSafe -> `String "safe"
  | K.StepBadAssumption -> `String "bad_assumption"
  | K.StepBadGuarantee -> `String "bad_guarantee"

let product_step_class_of_yojson = function
  | `String "safe" -> Ok K.StepSafe
  | `String "bad_assumption" -> Ok K.StepBadAssumption
  | `String "bad_guarantee" -> Ok K.StepBadGuarantee
  | `String raw -> Error ("product_step_class: unknown class " ^ raw)
  | _ -> Error "product_step_class: expected string"

let product_step_to_yojson (step : K.product_step) : Yojson.Safe.t =
  `Assoc
    [
      ("anchor", product_step_anchor_to_yojson step.K.step_anchor);
      ("program_guard", Core_syntax.hexpr_to_yojson step.K.program_guard);
      ("assume_guard", Core_syntax.hexpr_to_yojson step.K.assume_guard);
      ("guarantee_guard", Core_syntax.hexpr_to_yojson step.K.guarantee_guard);
      ("step_class", product_step_class_to_yojson step.K.step_class);
    ]

let product_step_of_yojson = function
  | `Assoc fields ->
      let* anchor_json = field fields "anchor" in
      let* program_guard_json = field fields "program_guard" in
      let* assume_guard_json = field fields "assume_guard" in
      let* guarantee_guard_json = field fields "guarantee_guard" in
      let* step_class_json = field fields "step_class" in
      let* step_anchor = product_step_anchor_of_yojson anchor_json in
      let* program_guard = Core_syntax.historical_hexpr_of_yojson program_guard_json in
      let* assume_guard = Core_syntax.historical_hexpr_of_yojson assume_guard_json in
      let* guarantee_guard = Core_syntax.historical_hexpr_of_yojson guarantee_guard_json in
      let* step_class = product_step_class_of_yojson step_class_json in
      Ok { K.step_anchor; program_guard; assume_guard; guarantee_guard; step_class }
  | _ -> Error "product_step: expected object"

let anchor_to_yojson = function
  | K.AnchorProductState st ->
      `Assoc [ ("kind", `String "product_state"); ("state", product_state_anchor_to_yojson st) ]
  | K.AnchorProductStep step ->
      `Assoc [ ("kind", `String "product_step"); ("step", product_step_anchor_to_yojson step) ]

let anchor_of_yojson = function
  | `Assoc fields -> (
      match string_field fields "kind" with
      | Error msg -> Error msg
      | Ok "product_state" ->
          let* state_json = field fields "state" in
          let* state = product_state_anchor_of_yojson state_json in
          Ok (K.AnchorProductState state)
      | Ok "product_step" ->
          let* step_json = field fields "step" in
          let* step = product_step_anchor_of_yojson step_json in
          Ok (K.AnchorProductStep step)
      | Ok raw -> Error ("anchor: unknown kind " ^ raw))
  | _ -> Error "anchor: expected object"

let timed_fact_desc_to_yojson = function
  | K.FactProgramState state ->
      `Assoc [ ("kind", `String "program_state"); ("state", `String state) ]
  | K.FactGuaranteeState state_index ->
      `Assoc [ ("kind", `String "guarantee_state"); ("state_index", `Int state_index) ]
  | K.FactPhaseFormula formula ->
      `Assoc [ ("kind", `String "phase_formula"); ("formula", Core_syntax.hexpr_to_yojson formula) ]
  | K.FactFormula formula ->
      `Assoc [ ("kind", `String "formula"); ("formula", Core_syntax.hexpr_to_yojson formula) ]
  | K.FactFalse -> `Assoc [ ("kind", `String "false") ]

let timed_fact_desc_of_yojson = function
  | `Assoc fields -> (
      match string_field fields "kind" with
      | Error msg -> Error msg
      | Ok "program_state" ->
          let* state = string_field fields "state" in
          Ok (K.FactProgramState state)
      | Ok "guarantee_state" ->
          let* state_index = int_field fields "state_index" in
          Ok (K.FactGuaranteeState state_index)
      | Ok "phase_formula" ->
          let* formula_json = field fields "formula" in
          let* formula = Core_syntax.historical_hexpr_of_yojson formula_json in
          Ok (K.FactPhaseFormula formula)
      | Ok "formula" ->
          let* formula_json = field fields "formula" in
          let* formula = Core_syntax.historical_hexpr_of_yojson formula_json in
          Ok (K.FactFormula formula)
      | Ok "false" -> Ok K.FactFalse
      | Ok raw -> Error ("timed_fact_desc: unknown kind " ^ raw))
  | _ -> Error "timed_fact_desc: expected object"

let timed_fact_to_yojson (fact : K.timed_fact) : Yojson.Safe.t =
  `Assoc
    [
      ("time", time_tag_to_yojson fact.K.tf_time);
      ("desc", timed_fact_desc_to_yojson fact.K.tf_desc);
    ]

let timed_fact_of_yojson = function
  | `Assoc fields ->
      let* time_json = field fields "time" in
      let* desc_json = field fields "desc" in
      let* tf_time = time_tag_of_yojson time_json in
      let* tf_desc = timed_fact_desc_of_yojson desc_json in
      Ok { K.tf_time; tf_desc }
  | _ -> Error "timed_fact: expected object"

let kernel_clause_to_yojson (clause : K.kernel_clause) : Yojson.Safe.t =
  `Assoc
    [
      ("anchor", anchor_to_yojson clause.K.kc_anchor);
      ("hypotheses", `List (List.map timed_fact_to_yojson clause.K.kc_hypotheses));
      ("conclusions", `List (List.map timed_fact_to_yojson clause.K.kc_conclusions));
    ]

let kernel_clause_of_yojson = function
  | `Assoc fields ->
      let* anchor_json = field fields "anchor" in
      let* hypotheses_json = field fields "hypotheses" in
      let* conclusions_json = field fields "conclusions" in
      let* kc_anchor = anchor_of_yojson anchor_json in
      let* kc_hypotheses = list_of_yojson timed_fact_of_yojson "hypotheses" hypotheses_json in
      let* kc_conclusions = list_of_yojson timed_fact_of_yojson "conclusions" conclusions_json in
      Ok { K.kc_anchor; kc_hypotheses; kc_conclusions }
  | _ -> Error "kernel_clause: expected object"

let clause_context_to_yojson = function
  | K.ClauseProductState state ->
      `Assoc [ ("kind", `String "product_state"); ("state", product_state_anchor_to_yojson state) ]
  | K.ClauseProductStep step ->
      `Assoc [ ("kind", `String "product_step"); ("step", product_step_to_yojson step) ]

let clause_context_of_yojson = function
  | `Assoc fields -> (
      match string_field fields "kind" with
      | Error msg -> Error msg
      | Ok "product_state" ->
          let* state_json = field fields "state" in
          let* state = product_state_anchor_of_yojson state_json in
          Ok (K.ClauseProductState state)
      | Ok "product_step" ->
          let* step_json = field fields "step" in
          let* step = product_step_of_yojson step_json in
          Ok (K.ClauseProductStep step)
      | Ok raw -> Error ("clause_context: unknown kind " ^ raw))
  | _ -> Error "clause_context: expected object"

let classified_clause_to_yojson (clause : K.classified_clause) : Yojson.Safe.t =
  `Assoc
    [
      ("family", clause_family_to_yojson clause.K.family);
      ("context", clause_context_to_yojson clause.K.context);
      ("clause", kernel_clause_to_yojson clause.K.clause);
    ]

let classified_clause_of_yojson = function
  | `Assoc fields ->
      let* family_json = field fields "family" in
      let* context_json = field fields "context" in
      let* clause_json = field fields "clause" in
      let* family = clause_family_of_yojson family_json in
      let* context = clause_context_of_yojson context_json in
      let* clause = kernel_clause_of_yojson clause_json in
      Ok { K.family; context; clause }
  | _ -> Error "classified_clause: expected object"
