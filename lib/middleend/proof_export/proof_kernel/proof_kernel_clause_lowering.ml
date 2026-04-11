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

open Pre_k_lowering
open Core_syntax
open Core_syntax_builders
open Proof_kernel_types

let is_hfalse (h : Core_syntax.hexpr) =
  match h.hexpr with HLitBool false -> true | _ -> false

let is_htrue (h : Core_syntax.hexpr) =
  match h.hexpr with HLitBool true -> true | _ -> false

let lower_clause_fact ~(temporal_bindings : Pre_k_lowering.temporal_binding list)
    (fact : clause_fact_ir) :
    clause_fact_ir option =
  let lower_desc = function
    | FactProgramState _ as desc -> Some desc
    | FactGuaranteeState _ as desc -> Some desc
    | FactPhaseFormula fo_formula ->
        Option.map (fun fo_formula' -> FactPhaseFormula fo_formula')
          (lower_fo_formula_temporal_bindings ~temporal_bindings fo_formula)
    | FactFalse -> Some FactFalse
    | FactFormula fo_formula ->
        Option.map (fun fo_formula' -> FactFormula fo_formula')
          (lower_fo_formula_temporal_bindings ~temporal_bindings fo_formula)
  in
  Option.map (fun desc -> { fact with desc }) (lower_desc fact.desc)

let lower_generated_clause ~(temporal_bindings : Pre_k_lowering.temporal_binding list)
    (clause : generated_clause_ir) : generated_clause_ir option =
  let rec lower_all acc = function
    | [] -> Some (List.rev acc)
    | fact :: tl -> (
        match lower_clause_fact ~temporal_bindings fact with
        | None -> None
        | Some fact' -> lower_all (fact' :: acc) tl)
  in
  match (lower_all [] clause.hypotheses, lower_all [] clause.conclusions) with
  | Some hypotheses, Some conclusions ->
      if
        List.exists
          (fun (fact : clause_fact_ir) ->
            fact.desc = FactFormula (mk_hbool false) || fact.desc = FactFalse)
          hypotheses
      then None
      else Some { clause with hypotheses; conclusions }
  | _ -> None

let relationalize_clause_fact ~(temporal_bindings : Pre_k_lowering.temporal_binding list)
    (fact : clause_fact_ir) : relational_clause_fact_ir option =
  let rel_desc = function
    | FactProgramState st -> Some (RelFactProgramState st)
    | FactGuaranteeState idx -> Some (RelFactGuaranteeState idx)
    | FactPhaseFormula fo_formula ->
        Option.map (fun fo_formula' -> RelFactPhaseFormula fo_formula')
          (lower_fo_formula_temporal_bindings ~temporal_bindings fo_formula)
    | FactFormula fo_formula ->
        Option.map (fun fo_formula' -> RelFactFormula fo_formula')
          (lower_fo_formula_temporal_bindings ~temporal_bindings fo_formula)
    | FactFalse -> Some RelFactFalse
  in
  Option.map (fun desc -> { time = fact.time; desc }) (rel_desc fact.desc)

let expand_relational_hypotheses (facts : relational_clause_fact_ir list) :
    relational_clause_fact_ir list list =
  let rec expand_one acc = function
    | [] -> [ List.rev acc ]
    | ({ desc = RelFactFormula ({ hexpr = HBin (Or, a, b); _ }); _ } as fact) :: tl ->
        let left = { fact with desc = RelFactFormula (Fo_simplifier.simplify_fo a) } in
        let right = { fact with desc = RelFactFormula (Fo_simplifier.simplify_fo b) } in
        (expand_one (left :: acc) tl) @ expand_one (right :: acc) tl
    | fact :: tl -> expand_one (fact :: acc) tl
  in
  expand_one [] facts

let normalize_relational_hypotheses (facts : relational_clause_fact_ir list) :
    relational_clause_fact_ir list option =
  let combine_formula left right =
    match (left, right) with
    | RelFactFormula a, RelFactFormula b ->
        Some (RelFactFormula (Fo_simplifier.simplify_fo (mk_hand a b)))
    | _ -> None
  in
  let rec insert acc fact =
    match acc with
    | [] -> Some [ fact ]
    | hd :: tl ->
        if hd.time = fact.time then
          match combine_formula hd.desc fact.desc with
          | Some (RelFactFormula h) when is_hfalse h -> None
          | Some desc -> Some ({ hd with desc } :: tl)
          | None -> Option.map (fun tl' -> hd :: tl') (insert tl fact)
        else
          Option.map (fun tl' -> hd :: tl') (insert tl fact)
  in
  let rec fold acc = function
    | [] ->
        Some
          (List.filter
             (fun (fact : relational_clause_fact_ir) ->
               match fact.desc with RelFactFormula h -> not (is_htrue h) | _ -> true)
             acc)
    | ({ desc = RelFactFormula h; _ } : relational_clause_fact_ir) :: _ when is_hfalse h -> None
    | ({ desc = RelFactFalse; _ } : relational_clause_fact_ir) :: _ -> None
    | fact :: tl -> (
        match insert acc fact with
        | None -> None
        | Some acc' -> fold acc' tl)
  in
  fold [] facts

let relationalize_generated_clause ~(temporal_bindings : Pre_k_lowering.temporal_binding list)
    (clause : generated_clause_ir) : relational_generated_clause_ir list =
  let lower_all facts = List.filter_map (relationalize_clause_fact ~temporal_bindings) facts in
  let hypotheses = lower_all clause.hypotheses in
  let conclusions = lower_all clause.conclusions in
  if conclusions = [] then []
  else
    expand_relational_hypotheses hypotheses
    |> List.filter_map (fun hypotheses ->
           match normalize_relational_hypotheses hypotheses with
           | None -> None
           | Some hypotheses -> Some { origin = clause.origin; anchor = clause.anchor; hypotheses; conclusions })
