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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Why3
open Ptree
open Core_syntax
open Why_compile_expr
open Why_compile_logic
open Why_compile_ptree_helpers

module StringSet = Why_compile_ptree_helpers.StringSet

type context = {
  env : Why_compile_expr.env;
  inputs : Ptree.binder list;
  runtime_view : Why_runtime_view.t;
  share_why3_facts : bool;
}

type t = {
  abstract_formula : in_post:bool -> Core_syntax.hexpr -> Ptree.term option;
  abstract_formula_with_rec : string -> Core_syntax.hexpr -> Ptree.term option;
  local_cut_candidate : Core_syntax.hexpr -> bool;
  shared_formula_names_in_terms : Ptree.term list -> StringSet.t;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Ptree.decl list;
}

type shared_entry = string * (ident * Ptree.pty) list * int * bool

let formula_key (formula : Core_syntax.hexpr) =
  Core_fo_simplifier.key_of_hexpr formula

let is_composite_fact (formula : Core_syntax.hexpr) =
  match formula.hexpr with
  | HBin (And, _, _) | HBin (Or, _, _) | HUn (Not, _) | HPred _ -> true
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HFunCall _
  | HUn (Neg, _)
  | HBin ((Add | Sub | Mul | Div), _, _)
  | HCmp _ ->
      false

let shared_formula_params env inputs =
  inputs
  |> List.filter_map (fun (_, id_opt, _, pty_opt) ->
         match (id_opt, pty_opt) with
         | Some id, Some pty when not (String.equal id.id_str env.rec_name) ->
             Some (id.id_str, pty)
         | _ -> None)

let params_for_formula shared_params (formula : Core_syntax.hexpr) =
  let vars = vars_of_hexpr StringSet.empty formula in
  List.filter (fun (param_name, _) -> StringSet.mem param_name vars) shared_params

let formula_uses_self env (formula : Core_syntax.hexpr) =
  let vars = vars_of_hexpr StringSet.empty formula in
  List.exists (fun rec_var -> StringSet.mem rec_var vars) env.rec_vars

let record_formula_occurrence stats ~scope (formula : Core_syntax.hexpr) =
  let key = formula_key formula in
  match Hashtbl.find_opt stats key with
  | Some (representative, count, scopes) ->
      Hashtbl.replace stats key
        (representative, count + 1, StringSet.add scope scopes)
  | None ->
      Hashtbl.add stats key (formula, 1, StringSet.singleton scope)

let add_summary_formulas stats ~scope formulas =
  List.iter
    (fun (formula : Ir.summary_formula) ->
      record_formula_occurrence stats ~scope formula.logic)
    formulas

let record_product_formulas stats (runtime_view : Why_runtime_view.t) =
  runtime_view.product_transitions
  |> List.iteri (fun idx (pc : Why_runtime_view.runtime_product_transition_view) ->
         let scope =
           Printf.sprintf "%d:%s:%s:%d:%d:%s" idx pc.transition_id
             pc.product_src.prog_state pc.product_src.assume_state_index
             pc.product_src.guarantee_state_index
             (match pc.step_class with
             | Why_runtime_view.StepSafe -> "safe"
             | Why_runtime_view.StepBadGuarantee -> "bad_guarantee")
         in
         add_summary_formulas stats ~scope pc.requires;
         add_summary_formulas stats ~scope pc.local_requires;
         (* Forbidden facts are emitted transparently under negation. Recording
            them here would create shared predicates that the proof path no
            longer calls. *)
         add_summary_formulas stats ~scope pc.ensures)

let select_shared_formulas env shared_params stats table order =
  Hashtbl.to_seq stats
  |> Seq.iter (fun (key, (formula, _count, scopes)) ->
         if is_composite_fact formula && StringSet.cardinal scopes > 1 then (
           let size = hexpr_size formula in
           let name =
             Printf.sprintf "shared_contract_formula_%03d"
               (Hashtbl.length table + 1)
           in
           let params = params_for_formula shared_params formula in
           let use_self = formula_uses_self env formula in
           Hashtbl.add table key (name, params, size, use_self);
           order := (name, params, formula, size) :: !order))

let shared_formula_call_with_rec rec_name name params use_self =
  let args =
    (if use_self then [ mk_term (Tident (qid1 rec_name)) ] else [])
    @ List.map (fun (param_name, _) -> mk_term (Tident (qid1 param_name))) params
  in
  mk_term (Tidapp (qid1 name, args))

let rec compile_shared_hexpr env table current_key rec_name formula =
  let key = formula_key formula in
  match Hashtbl.find_opt table key with
  | Some (name, params, _, use_self) when not (String.equal key current_key) ->
      shared_formula_call_with_rec rec_name name params use_self
  | _ ->
      let local_env = { env with rec_name } in
      begin
        match formula.hexpr with
        | HLitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
        | HLitBool b -> mk_term (if b then Ttrue else Tfalse)
        | HLitEnum c -> mk_term (Tident (qid1 c))
        | HVar x -> mk_term (term_var local_env x)
        | HPreK (_name, _k) ->
            failwith
              "compile_shared_hexpr: residual HPreK in Why3 emission input"
        | HUn (Neg, a) ->
            mk_term
              (Tidapp
                 ( qid1 "(-)",
                   [ compile_shared_hexpr env table current_key rec_name a ] ))
        | HUn (Not, a) ->
            mk_term (Tnot (compile_shared_hexpr env table current_key rec_name a))
        | HPred (id, hs) ->
            mk_term
              (Tidapp
                 ( qid1 id,
                   List.map
                     (compile_shared_hexpr env table current_key rec_name)
                     hs ))
        | HFunCall (fn, hs) ->
            mk_term
              (Tidapp
                 ( qid1 fn,
                   List.map
                     (compile_shared_hexpr env table current_key rec_name)
                     hs ))
        | HBin (And, a, b) ->
            term_bool_binop Dterm.DTand
              (compile_shared_hexpr env table current_key rec_name a)
              (compile_shared_hexpr env table current_key rec_name b)
        | HBin (Or, a, b) ->
            term_bool_binop Dterm.DTor
              (compile_shared_hexpr env table current_key rec_name a)
              (compile_shared_hexpr env table current_key rec_name b)
        | HBin (op, a, b) ->
            mk_term
              (Tinnfix
                 ( compile_shared_hexpr env table current_key rec_name a,
                   infix_ident (binop_id op),
                   compile_shared_hexpr env table current_key rec_name b ))
        | HCmp (op, a, b) ->
            mk_term
              (Tinnfix
                 ( compile_shared_hexpr env table current_key rec_name a,
                   infix_ident (relop_id op),
                   compile_shared_hexpr env table current_key rec_name b ))
      end

let build_shared_formula_entries env table order =
  !order
  |> List.sort (fun (_, _, _, size_a) (_, _, _, size_b) ->
         Int.compare size_a size_b)
  |> List.map (fun (name, params, formula, _) ->
         let body = compile_shared_hexpr env table (formula_key formula) "self" formula in
         let decl =
           logic_bool_pred_decl_with_body
             ~use_self:(formula_uses_self env formula)
             ~params ~name ~body
         in
         (name, formula, decl))

let shared_formula_names_in_term term =
  names_of_term term StringSet.empty
  |> StringSet.filter (String.starts_with ~prefix:"shared_contract_formula_")

let shared_formula_names_in_terms terms =
  List.fold_left
    (fun acc term -> StringSet.union acc (shared_formula_names_in_term term))
    StringSet.empty terms

let direct_shared_formula_deps table (formula : Core_syntax.hexpr) =
  let rec go current_key h acc =
    let key = formula_key h in
    match Hashtbl.find_opt table key with
    | Some (name, _, _, _) when not (String.equal key current_key) ->
        StringSet.add name acc
    | _ ->
        begin
          match h.hexpr with
          | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> acc
          | HUn (_, inner) -> go current_key inner acc
          | HPred (_, hs) | HFunCall (_, hs) ->
              List.fold_left (fun acc h -> go current_key h acc) acc hs
          | HBin (_, a, b) | HCmp (_, a, b) ->
              go current_key b (go current_key a acc)
        end
  in
  go (formula_key formula) formula StringSet.empty

let shared_formula_closure deps_by_name names =
  let rec loop seen work =
    match work with
    | [] -> seen
    | name :: rest ->
        if StringSet.mem name seen then loop seen rest
        else
          let deps =
            Option.value
              (List.assoc_opt name deps_by_name)
              ~default:StringSet.empty
            |> StringSet.elements
          in
          loop (StringSet.add name seen) (deps @ rest)
  in
  loop StringSet.empty (StringSet.elements names)

let local_cut_candidate (formula : Core_syntax.hexpr) =
  let emit_local_unfolded_cuts = false in
  emit_local_unfolded_cuts
  &&
  match formula.hexpr with
  | HBin ((And | Or), _, _) | HUn (Not, _) | HPred _ -> true
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HFunCall _
  | HUn (Neg, _)
  | HBin ((Add | Sub | Mul | Div), _, _)
  | HCmp _ ->
      false

let build ctx =
  let stats : (string, Core_syntax.hexpr * int * StringSet.t) Hashtbl.t =
    Hashtbl.create 128
  in
  let table : (string, shared_entry) Hashtbl.t = Hashtbl.create 128 in
  let order = ref [] in
  if ctx.share_why3_facts then (
    record_product_formulas stats ctx.runtime_view;
    select_shared_formulas ctx.env (shared_formula_params ctx.env ctx.inputs)
      stats table order);
  let shared_formula_call name params use_self =
    shared_formula_call_with_rec ctx.env.rec_name name params use_self
  in
  let abstract_formula ~in_post:_ (formula : Core_syntax.hexpr) =
    if not ctx.share_why3_facts then None
    else
      Hashtbl.find_opt table (formula_key formula)
      |> Option.map (fun (name, params, _, use_self) ->
             shared_formula_call name params use_self)
  in
  let abstract_formula_with_rec rec_name (formula : Core_syntax.hexpr) =
    if not ctx.share_why3_facts then None
    else
      Hashtbl.find_opt table (formula_key formula)
      |> Option.map (fun (name, params, _, use_self) ->
             shared_formula_call_with_rec rec_name name params use_self)
  in
  let shared_formula_entries =
    if not ctx.share_why3_facts then []
    else build_shared_formula_entries ctx.env table order
  in
  let deps_by_name =
    shared_formula_entries
    |> List.map (fun (name, formula, _decl) ->
           (name, direct_shared_formula_deps table formula))
  in
  let local_shared_formula_decls ?(exclude = StringSet.empty) names =
    let closure = StringSet.diff (shared_formula_closure deps_by_name names) exclude in
    shared_formula_entries
    |> List.filter_map (fun (name, _formula, decl) ->
           if StringSet.mem name closure then Some decl else None)
  in
  {
    abstract_formula;
    abstract_formula_with_rec;
    local_cut_candidate;
    shared_formula_names_in_terms;
    local_shared_formula_decls;
  }
