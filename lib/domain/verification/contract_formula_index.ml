(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Canonical propositional formulas reused by distinct contracts. *)

type formula_id = int

type definition = {
  id : formula_id;
  formula : Core_syntax.history_free Ir.summary_formula;
}

type occurrence = {
  formula : Core_syntax.history_free Ir.summary_formula;
  mutable last_contract : int;
  mutable contract_count : int;
  mutable oids_rev : Ir_shared_types.formula_id list;
}

type t = {
  definitions : definition list;
  by_oid : (Ir_shared_types.formula_id, definition) Hashtbl.t;
}

let shareable (formula : Core_syntax.history_free Ir.summary_formula) =
  match formula.logic.hexpr with
  | HBin ((And | Or), _, _) | HUn (Not, _) -> true
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _
  | HPred _ | HFunCall _ | HUn (Neg, _)
  | HBin ((Add | Sub | Mul | Div), _, _)
  | HCmp _ ->
      false

let build contracts =
  let occurrences = Hashtbl.create 128 in
  let key_by_oid = Hashtbl.create 128 in
  let order = ref [] in
  List.iteri
    (fun contract formulas ->
      formulas
      |> List.iter (fun (formula : Core_syntax.history_free Ir.summary_formula) ->
             let key = Formula_canonical.key formula.logic in
             let oid = formula.meta.oid in
             (match Hashtbl.find_opt key_by_oid oid with
             | None -> Hashtbl.add key_by_oid oid key
             | Some previous_key when previous_key = key -> ()
             | Some _ ->
                 invalid_arg
                   (Printf.sprintf
                      "Contract_formula_index.build: formula oid %d denotes \
                       structurally different formulas"
                      oid));
             if shareable formula then
               match Hashtbl.find_opt occurrences key with
               | None ->
                   Hashtbl.add occurrences key
                     {
                       formula;
                       last_contract = contract;
                       contract_count = 1;
                       oids_rev = [ oid ];
                     };
                   order := key :: !order
               | Some occurrence ->
                   occurrence.oids_rev <- oid :: occurrence.oids_rev;
                   if occurrence.last_contract <> contract then begin
                     occurrence.last_contract <- contract;
                     occurrence.contract_count <-
                       occurrence.contract_count + 1
                   end))
    contracts;
  let by_oid = Hashtbl.create 32 in
  let next_definition_id = ref 0 in
  let definitions =
    List.rev !order
    |> List.filter_map (fun key ->
           let occurrence = Hashtbl.find occurrences key in
           if occurrence.contract_count < 2 then None
           else
             let definition =
               {
                id = !next_definition_id;
                formula = occurrence.formula;
               }
             in
             incr next_definition_id;
             List.iter
               (fun oid -> Hashtbl.replace by_oid oid definition)
               occurrence.oids_rev;
             Some definition)
  in
  { definitions; by_oid }

let definitions index = index.definitions

let find index (formula : Core_syntax.history_free Ir.summary_formula) =
  Hashtbl.find_opt index.by_oid formula.meta.oid
