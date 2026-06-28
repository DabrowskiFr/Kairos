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

(** Lowering and normalization of generated clauses.

    This module filters impossible clauses, relationalizes facts, expands
    disjunctive hypotheses and normalizes conjunctions for proof export. *)

open Core_syntax
open Core_syntax_builders
open Proof_kernel_types

module K = Kernel_clause_projection

(** [simplify_fo] helper value. *)

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

(** [is_hfalse] helper value. *)

let is_hfalse (h : Core_syntax.hexpr) =
  match h.hexpr with HLitBool false -> true | _ -> false

(** [is_htrue] helper value. *)

let is_htrue (h : Core_syntax.hexpr) =
  match h.hexpr with HLitBool true -> true | _ -> false

(** [fact_desc_is_false] helper value. *)

let fact_desc_is_false = function
  | K.FactFormula h | K.FactPhaseFormula h -> is_hfalse h
  | K.FactFalse -> true
  | K.FactProgramState _ | K.FactGuaranteeState _ -> false

(** [fact_desc_is_true] helper value. *)

let fact_desc_is_true = function
  | K.FactFormula h | K.FactPhaseFormula h -> is_htrue h
  | K.FactFalse | K.FactProgramState _ | K.FactGuaranteeState _ -> false

(** [lower_generated_clause] helper value. *)

let lower_generated_clause (clause : generated_clause_ir) : generated_clause_ir option =
  let kernel_clause = clause.K.clause in
  if
    List.exists
      (fun (fact : K.timed_fact) -> fact_desc_is_false fact.K.tf_desc)
      kernel_clause.K.kc_hypotheses
  then None
  else (
    let hypotheses =
      List.filter
        (fun (fact : K.timed_fact) -> not (fact_desc_is_true fact.K.tf_desc))
        kernel_clause.K.kc_hypotheses
    in
    let conclusions =
      List.filter
        (fun (fact : K.timed_fact) -> not (fact_desc_is_true fact.K.tf_desc))
        kernel_clause.K.kc_conclusions
    in
    match conclusions with
    | [] -> None
    | _ ->
        Some
          {
            clause with
            K.clause = { kernel_clause with K.kc_hypotheses = hypotheses; kc_conclusions = conclusions };
          })

(** [relationalize_clause_fact] helper value. *)

let relationalize_clause_fact (fact : K.timed_fact) : relational_clause_fact_ir =
  let desc =
    match fact.K.tf_desc with
    | K.FactProgramState st -> RelFactProgramState st
    | K.FactGuaranteeState idx -> RelFactGuaranteeState idx
    | K.FactPhaseFormula fo_formula -> RelFactPhaseFormula fo_formula
    | K.FactFormula fo_formula -> RelFactFormula fo_formula
    | K.FactFalse -> RelFactFalse
  in
  { time = fact.K.tf_time; desc }

(** [rel_fact_desc_is_true] helper value. *)

let rel_fact_desc_is_true = function
  | RelFactFormula h | RelFactPhaseFormula h -> is_htrue h
  | RelFactFalse | RelFactProgramState _ | RelFactGuaranteeState _ -> false

(** [expand_relational_hypotheses] helper value. *)

let expand_relational_hypotheses (facts : relational_clause_fact_ir list) :
    relational_clause_fact_ir list list =
  let rec expand_one acc = function
    | [] -> [ List.rev acc ]
    | ({ desc = RelFactFormula ({ hexpr = HBin (Or, a, b); _ }); _ } as fact) :: tl ->
        let left = { fact with desc = RelFactFormula (simplify_fo a) } in
        let right = { fact with desc = RelFactFormula (simplify_fo b) } in
        (expand_one (left :: acc) tl) @ expand_one (right :: acc) tl
    | fact :: tl -> expand_one (fact :: acc) tl
  in
  expand_one [] facts

(** [normalize_relational_hypotheses] helper value. *)

let normalize_relational_hypotheses (facts : relational_clause_fact_ir list) :
    relational_clause_fact_ir list option =
  let combine_formula left right =
    match (left, right) with
    | RelFactFormula a, RelFactFormula b ->
        Some (RelFactFormula (simplify_fo (mk_hand a b)))
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
               match fact.desc with
               | RelFactFormula h | RelFactPhaseFormula h -> not (is_htrue h)
               | _ -> true)
             acc)
    | ({ desc = (RelFactFormula h | RelFactPhaseFormula h); _ } : relational_clause_fact_ir) :: _
      when is_hfalse h -> None
    | ({ desc = RelFactFalse; _ } : relational_clause_fact_ir) :: _ -> None
    | fact :: tl -> (
        match insert acc fact with
        | None -> None
        | Some acc' -> fold acc' tl)
  in
  fold [] facts

(** [relationalize_generated_clause] helper value. *)

let relationalize_generated_clause (clause : generated_clause_ir) : relational_generated_clause_ir list =
  let kernel_clause = clause.K.clause in
  let hypotheses = List.map relationalize_clause_fact kernel_clause.K.kc_hypotheses in
  let conclusions =
    kernel_clause.K.kc_conclusions
    |> List.map relationalize_clause_fact
    |> List.filter (fun (fact : relational_clause_fact_ir) -> not (rel_fact_desc_is_true fact.desc))
  in
  if conclusions = [] then []
  else
    expand_relational_hypotheses hypotheses
    |> List.filter_map (fun hypotheses ->
           match normalize_relational_hypotheses hypotheses with
           | None -> None
           | Some hypotheses ->
               Some
                 {
                   family = clause.K.family;
                   anchor = clause.K.context;
                   hypotheses;
                   conclusions;
                 })
