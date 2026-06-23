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

(** Main WhyML compiler from canonical IR.

    This module assembles Why3 module declarations (types, accessors, step
    helpers, contracts and goals) from {!Ir.node_ir} runtime views. *)

[@@@ocaml.warning "-8-26-27-32-33"]

(** Type [spec_groups]. *)

type spec_groups = { pre_labels : string list; post_labels : string list }

(** Type [program_ast]. *)

type program_ast = { mlw : Why3.Ptree.mlw_file; module_info : (string * spec_groups) list }

open Why3
open Ptree
open Core_syntax
open Pretty
open Pre_k_layout
open Why_compile_expr
open Why_compile_ptree_helpers
open Why_compile_logic

module StringSet = Why_compile_ptree_helpers.StringSet

(** [why_type_name] maps source enum type names to WhyML type identifiers.
    WhyML type identifiers are lowercase, while Kairos examples commonly use
    CamelCase enum names. *)
let why_type_name name =
  if String.equal name "state" then "state"
  else "kairos_" ^ String.uncapitalize_ascii name

(** [compile_seq] helper value. *)

let compile_seq = Why_compile_step.compile_seq
(** [compile_transition_body] helper value. *)

let compile_transition_body = Why_compile_step.compile_transition_body
(** [compile_state_body] helper value. *)

let compile_state_body = Why_compile_step.compile_state_body
(** [compile_transitions] helper value. *)

let compile_transitions = Why_compile_step.compile_transitions
(** [compile_runtime_view] helper value. *)

let compile_runtime_view = Why_compile_step.compile_runtime_view

(** [module_name_of_node] helper value. *)

let module_name_of_node (name : Core_syntax.ident) : string = String.capitalize_ascii name

(** Type [env_info]. *)

type env_info = {
  runtime_view : Why_runtime_view.t;
  module_name : string;
  imports : Why3.Ptree.decl list;
  type_enum_decls : Why3.Ptree.decl list;
  type_state : Why3.Ptree.decl;
  type_vars : Why3.Ptree.decl;
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
  ret_expr : Why3.Ptree.expr;
  hexpr_needs_old : hexpr -> bool;
  input_names : ident list;
}

(** [prepare_runtime_view] helper value. *)

let prepare_runtime_view ~(temporal_layout : Ir.temporal_layout) (runtime : Why_runtime_view.t) : env_info =
  let module_name = module_name_of_node runtime.node_name in
  let imports =
    [
      Ptree.Duseimport (loc, false, [ (qid1 "int.Int", None) ]);
      Ptree.Duseimport (loc, false, [ (qid1 "array.Array", None) ]);
    ]
  in
  let type_state =
    Ptree.Dtype
      [
        {
          td_loc = loc;
          td_ident = ident "state";
          td_params = [];
          td_vis = Public;
          td_mut = false;
          td_inv = [];
          td_wit = None;
          td_def = TDalgebraic (List.map (fun s -> (loc, ident s, [])) runtime.control_states);
        };
      ]
  in
  let type_enum_decls =
    runtime.type_decls
    |> List.map (fun (decl : enum_decl) ->
           Ptree.Dtype
             [
               {
          td_loc = loc;
          td_ident = ident (why_type_name decl.enum_name);
          td_params = [];
          td_vis = Public;
                 td_mut = false;
                 td_inv = [];
                 td_wit = None;
                 td_def =
                   TDalgebraic
                     (List.map (fun ctor -> (loc, ident ctor, [])) decl.enum_constructors);
               };
             ])
  in
  let pre_k_infos = temporal_layout in
  let inv_links = [] in
  let input_names = List.map (fun (p : Why_runtime_view.port_view) -> p.port_name) runtime.inputs in
  let base_vars =
    "st"
    :: List.map (fun (p : Why_runtime_view.port_view) -> p.port_name) (runtime.locals @ runtime.outputs)
  in
  let hexpr_needs_old (_h : hexpr) : bool = false in
  let env =
    {
      rec_name = "vars";
      rec_vars = base_vars;
      links = inv_links;
    }
  in
  let local_fields =
    List.map
      (fun v ->
        {
          f_loc = loc;
          f_ident = ident (v.Why_runtime_view.port_name);
          f_pty = default_pty v.port_type;
          f_mutable = true;
          f_ghost = false;
        })
      runtime.locals
  in
  let output_fields =
    List.map
      (fun v ->
        {
          f_loc = loc;
          f_ident = ident (v.Why_runtime_view.port_name);
          f_pty = default_pty v.port_type;
          f_mutable = true;
          f_ghost = false;
        })
      runtime.outputs
  in
  let fields : Ptree.field list =
    {
      f_loc = loc;
      f_ident = ident "st";
      f_pty = Ptree.PTtyapp (qid1 "state", []);
      f_mutable = true;
      f_ghost = false;
    }
    :: (local_fields @ output_fields)
  in
  let type_vars =
    Ptree.Dtype
      [
        {
          td_loc = loc;
          td_ident = ident "vars";
          td_params = [];
          td_vis = Public;
          td_mut = true;
          td_inv = [];
          td_wit = None;
          td_def = TDrecord fields;
        };
      ]
  in
  let output_exprs =
    List.map
      (fun (v : Why_runtime_view.port_view) -> field env v.port_name)
      runtime.outputs
  in
  let vars_param = (loc, Some (ident "vars"), false, Some (Ptree.PTtyapp (qid1 "vars", []))) in
  let input_binders =
    List.map
      (fun (v : Why_runtime_view.port_view) ->
        (loc, Some (ident v.port_name), false, Some (default_pty v.port_type)))
      runtime.inputs
  in
  let pre_k_binders =
    let seen = Hashtbl.create 16 in
    pre_k_infos
    |> List.concat_map (fun (info : Pre_k_layout.pre_k_info) ->
           info.names
           |> List.filter_map (fun name ->
                  if Hashtbl.mem seen name then None
                  else (
                    Hashtbl.add seen name ();
                    Some (loc, Some (ident name), false, Some (default_pty info.vty)))))
  in
  let inputs = vars_param :: (input_binders @ pre_k_binders) in
  let ret_expr =
    match output_exprs with
    | [] -> mk_expr (Etuple [])
    | [ e ] -> e
    | es -> mk_expr (Etuple es)
  in
  {
    runtime_view = runtime;
    module_name;
    imports;
    type_enum_decls;
    type_state;
    type_vars;
    env;
    inputs;
    ret_expr;
    hexpr_needs_old;
    input_names;
  }

(** [prepare_ir_node] helper value. *)

let prepare_ir_node ?(simplify_why3_runtime_actions = true)
    ?(slice_why3_transition_bodies = true) (node : Ir.node_ir) : env_info =
  let runtime =
    Why_runtime_view.of_ir_node
      ~simplify_runtime_actions:simplify_why3_runtime_actions
      ~slice_transition_bodies:slice_why3_transition_bodies node
  in
  prepare_runtime_view ~temporal_layout:node.temporal_layout runtime

(** Stable helper-name convention for per-product-step proof obligations.

    The proof runner uses this same function to map Why3 goal names back to
    their Kairos product-step origin. *)
let product_step_helper_name ~(index : int)
    (step : Why_runtime_view.runtime_product_transition_view) =
  let step_class_suffix = function
    | Why_runtime_view.StepSafe -> "safe"
    | Why_runtime_view.StepBadGuarantee -> "bad_guarantee"
  in
  Printf.sprintf "step_%s_ps_%s_a%d_g%d_%s_%d"
    (String.lowercase_ascii step.transition_id)
    (String.lowercase_ascii step.product_src.prog_state)
    step.product_src.assume_state_index
    step.product_src.guarantee_state_index
    (step_class_suffix step.step_class)
    index

let product_step_class_name = function
  | Why_runtime_view.StepSafe -> "safe"
  | Why_runtime_view.StepBadGuarantee -> "bad-guarantee"

let product_step_group_helper_name ~(index : int)
    (step : Why_runtime_view.runtime_product_transition_view) =
  let step_class_suffix = function
    | Why_runtime_view.StepSafe -> "safe_group"
    | Why_runtime_view.StepBadGuarantee -> "bad_guarantee_group"
  in
  Printf.sprintf "step_%s_%s_%d"
    (String.lowercase_ascii step.transition_id)
    (step_class_suffix step.step_class)
    index

(* Shared compilation core: all node-specific data is read from [info.runtime_view].
   The active path builds [info] from the IR via [prepare_ir_node]. *)
(** [compile_node_with_info] helper value. *)

let compile_node_with_info ?(share_why3_facts = true)
    ?(simplify_why3_formulas = true)
    ?(simplify_why3_runtime_actions = true)
    ?(deduplicate_why3_terms = true)
    ?(group_why3_product_steps = true)
    ?(why3_product_step_group_max_cost = 0)
    (info : env_info) :
    (Ptree.ident * Ptree.qualid option * Ptree.decl list * spec_groups) list =
  let runtime_view = info.runtime_view in
  let module_name = info.module_name in
  let imports = info.imports in
  let type_state = info.type_state in
  let type_enum_decls = info.type_enum_decls in
  let type_vars = info.type_vars in
  let env = info.env in
  let function_decls = List.map compile_pure_function_decl runtime_view.function_decls in
  let inputs = info.inputs in
  let ret_expr = info.ret_expr in
  (* Locals and outputs as vdecl list (needed for getter generation). *)
  let locals_and_outputs =
    List.map port_view_to_vdecl (runtime_view.locals @ runtime_view.outputs)
  in
  let getter_decls =
    let mk_getter (v : vdecl) =
      let field_name = v.vname in
      let getter_name = ident ("get_" ^ field_name) in
      let arg = (loc, Some (ident "self"), false, Some (Ptree.PTtyapp (qid1 "vars", []))) in
      let body = compile_expr { env with rec_name = "self" } { expr = EVar field_name; loc = None } in
      let fn =
        mk_expr
          (Efun
             ( [ arg ],
               Some (default_pty v.vty),
               { pat_desc = Pwild; pat_loc = loc },
               Ity.MaskVisible,
               empty_spec (),
               body ))
      in
      Ptree.Dlet (getter_name, false, Expr.RKnone, fn)
    in
    List.map mk_getter locals_and_outputs
  in
  let logic_getter_decls =
    let mk (v : vdecl) = logic_getter_decl ~env v.vname v.vty in
    logic_getter_decl ~env "st" (TCustom "state") :: List.map mk locals_and_outputs
  in
  let shared_formula_params =
    inputs
    |> List.filter_map (fun (_, id_opt, _, pty_opt) ->
           match (id_opt, pty_opt) with
           | Some id, Some pty when not (String.equal id.id_str env.rec_name) -> Some (id.id_str, pty)
           | _ -> None)
  in
  let formula_key (formula : Core_syntax.hexpr) =
    Core_fo_simplifier.key_of_hexpr formula
  in
  let shared_formula_stats : (string, Core_syntax.hexpr * int * StringSet.t) Hashtbl.t =
    Hashtbl.create 128
  in
  let shared_formula_table : (string, string * (ident * Ptree.pty) list * int * bool) Hashtbl.t =
    Hashtbl.create 128
  in
  let shared_formula_order = ref [] in
  let is_composite_fact (formula : Core_syntax.hexpr) =
    match formula.hexpr with
    | HBin (And, _, _) | HBin (Or, _, _) | HUn (Not, _) | HPred _ -> true
    | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HFunCall _
    | HUn (Neg, _) | HBin ((Add | Sub | Mul | Div), _, _) | HCmp _ ->
        false
  in
  let params_for_formula (formula : Core_syntax.hexpr) =
    let vars = vars_of_hexpr StringSet.empty formula in
    List.filter (fun (param_name, _) -> StringSet.mem param_name vars) shared_formula_params
  in
  let formula_uses_self (formula : Core_syntax.hexpr) =
    let vars = vars_of_hexpr StringSet.empty formula in
    List.exists (fun rec_var -> StringSet.mem rec_var vars) env.rec_vars
  in
  let record_formula_occurrence ~scope (formula : Core_syntax.hexpr) =
    let key = formula_key formula in
    match Hashtbl.find_opt shared_formula_stats key with
    | Some (representative, count, scopes) ->
        Hashtbl.replace shared_formula_stats key
          (representative, count + 1, StringSet.add scope scopes)
    | None ->
        Hashtbl.add shared_formula_stats key
          (formula, 1, StringSet.singleton scope)
  in
  let add_summary_formulas ~scope formulas =
    List.iter
      (fun (formula : Ir.summary_formula) -> record_formula_occurrence ~scope formula.logic)
      formulas
  in
  if share_why3_facts then
    List.iteri
      (fun idx (pc : Why_runtime_view.runtime_product_transition_view) ->
        let scope =
          Printf.sprintf "%d:%s:%s:%d:%d:%s" idx pc.transition_id
            pc.product_src.prog_state pc.product_src.assume_state_index
            pc.product_src.guarantee_state_index
            (match pc.step_class with
            | Why_runtime_view.StepSafe -> "safe"
            | Why_runtime_view.StepBadGuarantee -> "bad_guarantee")
        in
        add_summary_formulas ~scope pc.requires;
        add_summary_formulas ~scope pc.local_requires;
        (* Forbidden facts are emitted transparently under negation.  Recording
           them here would create shared predicates that the proof path no
           longer calls. *)
        add_summary_formulas ~scope pc.ensures)
      runtime_view.product_transitions;
  if share_why3_facts then
    Hashtbl.to_seq shared_formula_stats
    |> Seq.iter (fun (key, (formula, _count, scopes)) ->
           if is_composite_fact formula && StringSet.cardinal scopes > 1 then (
             let size = hexpr_size formula in
             let name =
               Printf.sprintf "shared_contract_formula_%03d"
                 (Hashtbl.length shared_formula_table + 1)
             in
             let params = params_for_formula formula in
             let use_self = formula_uses_self formula in
             Hashtbl.add shared_formula_table key (name, params, size, use_self);
             shared_formula_order := (name, params, formula, size) :: !shared_formula_order));
  let shared_formula_call_with_rec rec_name name params use_self =
    let args =
      (if use_self then [ mk_term (Tident (qid1 rec_name)) ] else [])
      @ List.map
          (fun (param_name, _) -> mk_term (Tident (qid1 param_name)))
          params
    in
    mk_term (Tidapp (qid1 name, args))
  in
  let shared_formula_call name params use_self =
    shared_formula_call_with_rec env.rec_name name params use_self
  in
  let rec compile_shared_hexpr current_key rec_name formula =
    let key = formula_key formula in
    match Hashtbl.find_opt shared_formula_table key with
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
              mk_term (Tidapp (qid1 "(-)", [ compile_shared_hexpr current_key rec_name a ]))
          | HUn (Not, a) -> mk_term (Tnot (compile_shared_hexpr current_key rec_name a))
          | HPred (id, hs) ->
              mk_term
                (Tidapp
                   (qid1 id, List.map (compile_shared_hexpr current_key rec_name) hs))
          | HFunCall (fn, hs) ->
              mk_term
                (Tidapp
                   (qid1 fn, List.map (compile_shared_hexpr current_key rec_name) hs))
          | HBin (And, a, b) ->
              term_bool_binop Dterm.DTand
                (compile_shared_hexpr current_key rec_name a)
                (compile_shared_hexpr current_key rec_name b)
          | HBin (Or, a, b) ->
              term_bool_binop Dterm.DTor
                (compile_shared_hexpr current_key rec_name a)
                (compile_shared_hexpr current_key rec_name b)
          | HBin (op, a, b) ->
              mk_term
                (Tinnfix
                   ( compile_shared_hexpr current_key rec_name a,
                     infix_ident (binop_id op),
                     compile_shared_hexpr current_key rec_name b ))
          | HCmp (op, a, b) ->
              mk_term
                (Tinnfix
                   ( compile_shared_hexpr current_key rec_name a,
                     infix_ident (relop_id op),
                     compile_shared_hexpr current_key rec_name b ))
        end
  in
  let abstract_formula ~in_post:_ (formula : Core_syntax.hexpr) =
    if not share_why3_facts then None
    else
      Hashtbl.find_opt shared_formula_table (formula_key formula)
      |> Option.map (fun (name, params, _, use_self) ->
             shared_formula_call name params use_self)
  in
  let abstract_formula_with_rec rec_name (formula : Core_syntax.hexpr) =
    if not share_why3_facts then None
    else
      Hashtbl.find_opt shared_formula_table (formula_key formula)
      |> Option.map (fun (name, params, _, use_self) ->
             shared_formula_call_with_rec rec_name name params use_self)
  in
  let emit_local_unfolded_cuts = false in
  let local_cut_candidate (formula : Core_syntax.hexpr) =
    emit_local_unfolded_cuts
    &&
    match formula.hexpr with
    | HBin ((And | Or), _, _) | HUn (Not, _) | HPred _ -> true
    | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HFunCall _
    | HUn (Neg, _) | HBin ((Add | Sub | Mul | Div), _, _) | HCmp _ ->
        false
  in
  let shared_formula_entries =
    if not share_why3_facts then []
    else
      !shared_formula_order
      |> List.sort (fun (_, _, _, size_a) (_, _, _, size_b) -> Int.compare size_a size_b)
      |> List.map (fun (name, params, formula, _) ->
             let body = compile_shared_hexpr (formula_key formula) "self" formula in
             let decl =
               logic_bool_pred_decl_with_body ~use_self:(formula_uses_self formula)
                 ~params ~name ~body
             in
             (name, formula, decl))
  in
  let shared_formula_decls =
    List.map (fun (_name, _formula, decl) -> decl) shared_formula_entries
  in
  let shared_formula_names_in_term term =
    names_of_term term StringSet.empty
    |> StringSet.filter (String.starts_with ~prefix:"shared_contract_formula_")
  in
  let shared_formula_names_in_terms terms =
    List.fold_left
      (fun acc term -> StringSet.union acc (shared_formula_names_in_term term))
      StringSet.empty terms
  in
  let direct_shared_formula_deps (formula : Core_syntax.hexpr) =
    let rec go current_key h acc =
      let key = formula_key h in
      match Hashtbl.find_opt shared_formula_table key with
      | Some (name, _, _, _) when not (String.equal key current_key) ->
          StringSet.add name acc
      | _ -> begin
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
  in
  let shared_formula_deps_by_name =
    shared_formula_entries
    |> List.map (fun (name, formula, _decl) -> (name, direct_shared_formula_deps formula))
  in
  let shared_formula_closure names =
    let rec loop seen work =
      match work with
      | [] -> seen
      | name :: rest ->
          if StringSet.mem name seen then loop seen rest
          else
            let deps =
              Option.value (List.assoc_opt name shared_formula_deps_by_name)
                ~default:StringSet.empty
              |> StringSet.elements
            in
            loop (StringSet.add name seen) (deps @ rest)
    in
    loop StringSet.empty (StringSet.elements names)
  in
  let local_shared_formula_decls ?(exclude = StringSet.empty) names =
    let closure = StringSet.diff (shared_formula_closure names) exclude in
    shared_formula_entries
    |> List.filter_map (fun (name, _formula, decl) ->
           if StringSet.mem name closure then Some decl else None)
  in
  let contracts =
    Why_contracts.build_contracts ~abstract_formula ~local_cut_candidate ~env:info.env
      ~hexpr_needs_old:info.hexpr_needs_old ~runtime:runtime_view ~pure_translation:false
      ~simplify_formulas:simplify_why3_formulas
      ~deduplicate_terms:deduplicate_why3_terms
  in
  let pre = contracts.pre in
  let post = contracts.post in
  let pre_labels = contracts.pre_labels in
  let post_labels = contracts.post_labels in
  let pre_source_states = contracts.pre_source_states in
  let post_source_states = contracts.post_source_states in
  let post_vcids = contracts.post_vcids in
  let step_contracts = contracts.step_contracts in
  let use_product_helper_contracts = step_contracts <> [] in

  (* In kernel-first relational mode, helper-local proof facts must come from
     relational preconditions, not from re-executing product-state tracking. *)
  let branch_sticky_asserts = [] in
  let branch_entry_asserts =
    if use_product_helper_contracts then []
    else
      let maybe_uniq terms = if deduplicate_why3_terms then uniq_terms terms else terms in
      let add_assert acc state_name term =
        let prev = Option.value ~default:[] (List.assoc_opt state_name acc) in
        (state_name, term :: prev) :: List.remove_assoc state_name acc
      in
      pre
      |> List.mapi (fun idx term -> (idx, term))
      |> List.fold_left
           (fun acc (idx, term) ->
             match List.nth_opt pre_source_states idx with
             | Some (Some state_name) -> add_assert acc state_name term
             | _ -> acc)
           []
      |> List.map (fun (state_name, terms) -> (state_name, List.rev (maybe_uniq terms)))
  in
  let full_step_body () = compile_runtime_view env runtime_view in
  let pre = pre in
  let post = post in
  let add_vcid_attr vcid_opt term =
    match vcid_opt with
    | None -> term
    | Some vcid -> mk_term (Tattr (ATstr (Ident.create_attribute vcid), term))
  in
  let post = List.map2 add_vcid_attr post_vcids post in
  let helper_args = List.map binder_expr inputs in

  let state_names = runtime_view.control_states in
  let rec strip_term_attrs (term : Ptree.term) : Ptree.term =
    match term.term_desc with Tattr (_, inner) -> strip_term_attrs inner | _ -> term
  in
  let qid_matches (qid : Ptree.qualid) (name : string) : bool = String.equal (string_of_qid qid) name in
  let state_ctor_name = function
    | { Ptree.term_desc = Tident (Qident id); _ } -> Some id.id_str
    | _ -> None
  in
  let state_eq_name (lhs : Ptree.term) (rhs : Ptree.term) : ident option =
    let lhs = strip_term_attrs lhs in
    let rhs = strip_term_attrs rhs in
    match (lhs.term_desc, rhs.term_desc) with
    | Tident q, _ when qid_matches q (env.rec_name ^ ".st") -> state_ctor_name rhs
    | _, Tident q when qid_matches q (env.rec_name ^ ".st") -> state_ctor_name lhs
    | _ -> None
  in
  let rec collect_state_mentions ~(old_state : bool) ~(inside_old : bool) (term : Ptree.term)
      (acc : ident list) : ident list =
    let term = strip_term_attrs term in
    match term.term_desc with
    | Tapply (fn, arg) -> begin
        match (strip_term_attrs fn).term_desc with
        | Tident q when qid_matches q "old" -> collect_state_mentions ~old_state ~inside_old:true arg acc
        | _ ->
            let acc = collect_state_mentions ~old_state ~inside_old fn acc in
            collect_state_mentions ~old_state ~inside_old arg acc
      end
    | Tinnfix (lhs, op, rhs) ->
        let acc =
          if op.id_str = "=" && Bool.equal inside_old old_state then
            match state_eq_name lhs rhs with Some st -> st :: acc | None -> acc
          else acc
        in
        let acc = collect_state_mentions ~old_state ~inside_old lhs acc in
        collect_state_mentions ~old_state ~inside_old rhs acc
    | Tbinnop (lhs, _, rhs) ->
        let acc = collect_state_mentions ~old_state ~inside_old lhs acc in
        collect_state_mentions ~old_state ~inside_old rhs acc
    | Tnot inner -> collect_state_mentions ~old_state ~inside_old inner acc
    | Tidapp (_q, args) -> List.fold_left (fun acc arg -> collect_state_mentions ~old_state ~inside_old arg acc) acc args
    | Tif (c, t_then, t_else) ->
        let acc = collect_state_mentions ~old_state ~inside_old c acc in
        let acc = collect_state_mentions ~old_state ~inside_old t_then acc in
        collect_state_mentions ~old_state ~inside_old t_else acc
    | Ttuple terms ->
        List.fold_left (fun acc arg -> collect_state_mentions ~old_state ~inside_old arg acc) acc terms
    | Tident _ | Tconst _ | Ttrue | Tfalse -> acc
    | _ -> acc
  in
  let classify_by_state ~(old_state : bool) (term : Ptree.term) : ident option =
    let focus =
      match (strip_term_attrs term).term_desc with
      | Tbinnop (lhs, Dterm.DTimplies, _rhs) -> lhs
      | _ -> term
    in
    let mentioned =
      collect_state_mentions ~old_state ~inside_old:false focus []
      |> List.filter (fun st -> List.mem st state_names)
      |> List.sort_uniq String.compare
    in
    match mentioned with
    | [ st ] -> Some st
    | _ -> None
  in
  let keep_for_state ~old_state state_name term =
    match classify_by_state ~old_state term with
    | Some st -> st = state_name
    | None -> true
  in
  let helper_spec_for_state state_name =
    let state_guard =
      term_eq (term_of_var env "st") (mk_term (Tident (qid1 state_name)))
    in
        let helper_pre =
          state_guard
          :: List.filteri
              (fun idx term ->
            match List.nth_opt pre_source_states idx with
            | Some (Some tagged_state) -> String.equal tagged_state state_name
            | _ -> keep_for_state ~old_state:false state_name term)
              pre
    in
    let helper_post =
      List.filteri
        (fun idx term ->
          match List.nth_opt post_source_states idx with
          | Some (Some tagged_state) -> String.equal tagged_state state_name
          | _ -> keep_for_state ~old_state:true state_name term)
        post
    in
    (helper_pre, helper_post)
  in
  let step_helper_name ~(index : int) (sc : Why_contracts.step_contract_info) =
    product_step_helper_name ~index sc.step
  in
  let import_module name =
    Ptree.Duseimport (loc, false, [ (qid1 name, None) ])
  in
  let common_module_name = module_name ^ "__Common" in
  let common_import = import_module common_module_name in
  let predicate_bundle_decl_and_call ~(name : string) (terms : Ptree.term list) =
    let body = term_and_list terms in
    let used = names_of_term body StringSet.empty in
    let used_inputs =
      inputs
      |> List.filter (fun (_, id_opt, _, _) ->
             match id_opt with
             | Some id -> StringSet.mem id.id_str used
             | None -> false)
    in
    let params = List.filter_map param_of_binder used_inputs in
    let args = List.filter_map binder_term used_inputs in
    let decl =
      Ptree.Dlogic
        [
          {
            ld_loc = loc;
            ld_ident = ident name;
            ld_params = params;
            ld_type = None;
            ld_def = Some body;
          };
        ]
    in
    (decl, mk_term (Tidapp (qid1 name, args)))
  in
  let shared_bundle_call ~(module_suffix : string) ~(predicate_prefix : string)
      ~(table : (string, string * string) Hashtbl.t) ~modules (terms : Ptree.term list) =
    let body = term_and_list terms in
    let key = string_of_term body in
    let shared_names = shared_formula_names_in_terms [ body ] in
    let used_names = names_of_term body StringSet.empty in
    let bundle_imports =
      Hashtbl.to_seq_values table
      |> Seq.filter_map (fun (bundle_module_name, name) ->
             if StringSet.mem name used_names then
               Some (import_module bundle_module_name)
             else None)
      |> List.of_seq
    in
    let used_inputs =
      inputs
      |> List.filter (fun (_, id_opt, _, _) ->
             match id_opt with
             | Some id -> StringSet.mem id.id_str used_names
             | None -> false)
    in
    let params = List.filter_map param_of_binder used_inputs in
    let args = List.filter_map binder_term used_inputs in
    let bundle_module_name, name =
      match Hashtbl.find_opt table key with
      | Some existing -> existing
      | None ->
          let index = Hashtbl.length table + 1 in
          let bundle_module_name =
            Printf.sprintf "%s__%s_%03d" module_name module_suffix index
          in
          let name = Printf.sprintf "%s_%03d" predicate_prefix index in
          let decl =
            Ptree.Dlogic
              [
                {
                  ld_loc = loc;
                  ld_ident = ident name;
                  ld_params = params;
                  ld_type = None;
                  ld_def = Some body;
                };
              ]
          in
          Hashtbl.add table key (bundle_module_name, name);
          let shared_decls = local_shared_formula_decls shared_names in
          modules :=
            ( ident bundle_module_name,
              None,
              imports @ [ common_import ] @ bundle_imports @ shared_decls @ [ decl ],
              { pre_labels = []; post_labels = [] } )
            :: !modules;
          (bundle_module_name, name)
    in
    (import_module bundle_module_name, mk_term (Tidapp (qid1 name, args)), shared_names)
  in
  let shared_post_bundle_table : (string, string * string) Hashtbl.t = Hashtbl.create 128 in
  let shared_post_bundle_modules = ref [] in
  let shared_post_bundle_call =
    shared_bundle_call ~module_suffix:"Post" ~predicate_prefix:"shared_post_bundle"
      ~table:shared_post_bundle_table ~modules:shared_post_bundle_modules
  in
  let shared_pre_bundle_table : (string, string * string) Hashtbl.t = Hashtbl.create 128 in
  let shared_pre_bundle_modules = ref [] in
  let shared_pre_bundle_call =
    shared_bundle_call ~module_suffix:"Pre" ~predicate_prefix:"shared_pre_bundle"
      ~table:shared_pre_bundle_table ~modules:shared_pre_bundle_modules
  in
  let contract_formula_term ~in_post logic =
    match abstract_formula ~in_post logic with
    | Some term -> term
    | None ->
        let normalized =
          if simplify_why3_formulas then Core_fo_simplifier.simplify logic
          else logic
        in
        begin
          match abstract_formula ~in_post normalized with
          | Some term -> term
          | None -> compile_local_fo_formula_term ~in_post env normalized
        end
  in
  let formula_family_is families (formula : Ir.summary_formula) =
    match formula.meta.family with
    | None -> false
    | Some family -> List.mem family families
  in
  let sorted_unique_terms terms =
    terms
    |> List.sort_uniq (fun left right ->
           String.compare (string_of_term left) (string_of_term right))
  in
  let selected_family_terms ~in_post families formulas =
    formulas
    |> List.filter (formula_family_is families)
    |> List.map (fun (formula : Ir.summary_formula) ->
           contract_formula_term ~in_post formula.logic)
    |> sorted_unique_terms
  in
  let remove_terms removed terms =
    let removed_keys =
      removed
      |> List.map string_of_term
      |> List.fold_left (fun acc key -> StringSet.add key acc) StringSet.empty
    in
    List.filter
      (fun term -> not (StringSet.mem (string_of_term term) removed_keys))
      terms
  in
  let bundle_key terms = string_of_term (term_and_list terms) in
  let count_bundles bundles =
    let counts = Hashtbl.create 64 in
    List.iter
      (fun terms ->
        if List.length terms > 1 then
          let key = bundle_key terms in
          let count = Option.value ~default:0 (Hashtbl.find_opt counts key) in
          Hashtbl.replace counts key (count + 1))
      bundles;
    counts
  in
  let shared_pre_families =
    [ "state_invariant_requires"; "stability_requires" ]
  in
  let shared_post_families = [ "common_destination_invariant_ensures" ] in
  let pre_family_terms_by_step =
    if not share_why3_facts then List.map (fun _ -> []) step_contracts
    else
      step_contracts
      |> List.map (fun (sc : Why_contracts.step_contract_info) ->
             selected_family_terms ~in_post:false shared_pre_families
               sc.step.requires)
  in
  let post_family_terms_by_step =
    if not share_why3_facts then List.map (fun _ -> []) step_contracts
    else
      step_contracts
      |> List.map (fun (sc : Why_contracts.step_contract_info) ->
             selected_family_terms ~in_post:true shared_post_families
               sc.step.ensures)
  in
  let pre_family_bundle_counts = count_bundles pre_family_terms_by_step in
  let post_family_bundle_counts = count_bundles post_family_terms_by_step in
  let should_share_bundle counts terms =
    List.length terms > 1
    &&
    match Hashtbl.find_opt counts (bundle_key terms) with
    | Some count -> count > 1
    | None -> false
  in
  let mk_post term = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, term) ]) in
  let seq_exprs (exprs : Ptree.expr list) =
    let exprs =
      List.filter
        (fun expr -> match expr.expr_desc with Etuple [] -> false | _ -> true)
        exprs
    in
    match exprs with
    | [] -> mk_expr (Etuple [])
    | first :: rest ->
        List.fold_left (fun acc expr -> mk_expr (Esequence (acc, expr))) first rest
  in
  let helper_function helper_inputs spc helper_body =
    mk_expr
      (Efun
         ( helper_inputs,
           None,
           { pat_desc = Pwild; pat_loc = loc },
           Ity.MaskVisible,
           spc,
           helper_body ))
  in
  let build_individual_kernel_helper (i, (sc : Why_contracts.step_contract_info)) =
    let t =
      Why_runtime_view.transition_of_product_step
        ~simplify_runtime_actions:simplify_why3_runtime_actions sc.step
    in
    let helper_name = ident (step_helper_name ~index:i sc) in
    let state_guard =
      term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.src_state)))
    in
    let pre_family_terms =
      Option.value ~default:[] (List.nth_opt pre_family_terms_by_step i)
    in
    let share_pre_family_bundle =
      should_share_bundle pre_family_bundle_counts pre_family_terms
    in
    let pre_terms =
      if share_pre_family_bundle then remove_terms pre_family_terms sc.pre
      else sc.pre
    in
    let pre_family_imports, pre_family_terms =
      if share_pre_family_bundle then
        let import_, call, _shared_names =
          shared_pre_bundle_call pre_family_terms
        in
        ([ import_ ], [ call ])
      else ([], [])
    in
    let post_family_terms =
      Option.value ~default:[] (List.nth_opt post_family_terms_by_step i)
    in
    let share_post_family_bundle =
      should_share_bundle post_family_bundle_counts post_family_terms
      && not (List.exists term_has_old post_family_terms)
    in
    let post_terms =
      if share_post_family_bundle then remove_terms post_family_terms sc.post
      else sc.post
    in
    let post_family_imports, post_family_terms, post_family_shared_names =
      if share_post_family_bundle then
        let import_, call, shared_names =
          shared_post_bundle_call post_family_terms
        in
        ([ import_ ], [ call ], shared_names)
      else ([], [], StringSet.empty)
    in
    let raw_pre_terms = state_guard :: (pre_family_terms @ pre_terms) in
    let raw_post_terms = sc.forbidden @ post_family_terms @ post_terms in
    let bundle_post_terms =
      List.length raw_post_terms > 1
      && not (List.exists term_has_old raw_post_terms)
    in
    let pre_bundle_decls, pre_term =
      let pre_decl, call =
        predicate_bundle_decl_and_call
          ~name:(helper_name.id_str ^ "_pre")
          raw_pre_terms
      in
      ([ pre_decl ], call)
    in
    let post_bundle_decls, post_terms, imported_shared_names =
      if not bundle_post_terms then
        (post_family_imports, raw_post_terms, post_family_shared_names)
      else
        let post_import, call, shared_names =
          shared_post_bundle_call raw_post_terms
        in
        (post_family_imports @ [ post_import ], [ call ],
         StringSet.union post_family_shared_names shared_names)
    in
    let spc =
      {
        Ptree.sp_pre = [ pre_term ];
        sp_post = List.rev_map mk_post post_terms;
        sp_xpost = [];
        sp_reads = [];
        sp_writes = [];
        sp_alias = [];
        sp_variant = [];
        sp_checkrw = false;
        sp_diverge = false;
        sp_partial = false;
      }
    in
    let local_cut_asserts =
      sc.local_cuts
      |> List.map (fun term -> mk_expr (Eassert (Expr.Assert, term)))
    in
    let helper_body =
      seq_exprs (compile_transition_body env [] t :: local_cut_asserts)
    in
    let direct_shared_terms =
      raw_pre_terms
      @ (if bundle_post_terms then [] else raw_post_terms)
      @ sc.local_cuts
    in
    let local_shared_decls =
      direct_shared_terms
      |> shared_formula_names_in_terms
      |> local_shared_formula_decls ~exclude:imported_shared_names
    in
    let helper_inputs =
      helper_binders_without_unused_parameters inputs spc helper_body
    in
    let fn = helper_function helper_inputs spc helper_body in
    ( helper_name.id_str,
      post_bundle_decls @ local_shared_decls @ pre_family_imports
      @ pre_bundle_decls
      @ [ Ptree.Dlet (helper_name, false, Expr.RKnone, fn) ] )
  in
  let input_binders_without_vars =
    match inputs with _vars :: rest -> rest | [] -> []
  in
  let predicate_param_of_name name =
    (loc, Some (ident name), false, Ptree.PTtyapp (qid1 "vars", []))
  in
  let formula_term_with_rec ?(allow_shared = true) ~in_post rec_name logic =
    let normalized =
      if simplify_why3_formulas then Core_fo_simplifier.simplify logic
      else logic
    in
    if allow_shared then
      match abstract_formula_with_rec rec_name logic with
      | Some term -> term
      | None -> begin
          match abstract_formula_with_rec rec_name normalized with
          | Some term -> term
          | None ->
              let local_env = { env with rec_name } in
              compile_local_fo_formula_term ~in_post local_env normalized
        end
    else
      let local_env = { env with rec_name } in
      compile_local_fo_formula_term ~in_post local_env normalized
  in
  let state_guard_with_rec rec_name state_name =
    let local_env = { env with rec_name } in
    term_eq (term_of_var local_env "st") (mk_term (Tident (qid1 state_name)))
  in
  let step_pre_terms_with_rec rec_name (sc : Why_contracts.step_contract_info) =
    state_guard_with_rec rec_name sc.step.src_state
    :: ((sc.step.requires @ sc.step.local_requires)
       |> List.concat_map (fun (formula : Ir.summary_formula) ->
              [ formula_term_with_rec ~in_post:false rec_name formula.logic ]))
  in
  let step_post_terms_with_rec rec_name (sc : Why_contracts.step_contract_info) =
    let forbidden =
      sc.step.forbidden
      |> List.map (fun (formula : Ir.summary_formula) ->
             mk_term
               (Tnot
                  (formula_term_with_rec ~allow_shared:false ~in_post:true
                     rec_name formula.logic)))
    in
    let ensures =
      sc.step.ensures
      |> List.map (fun (formula : Ir.summary_formula) ->
             formula_term_with_rec ~in_post:true rec_name formula.logic)
    in
    forbidden @ ensures
  in
  let pre_vars_name = "__pre_vars" in
  let post_vars_name = "__post_vars" in
  let unique_term_count terms =
    terms
    |> List.map string_of_term
    |> List.sort_uniq String.compare
    |> List.length
  in
  let grouped_kernel_terms entries =
    let pre_terms =
      entries
      |> List.map (fun (_i, sc, _t) ->
             step_pre_terms_with_rec env.rec_name sc |> term_and_list)
    in
    let pre_term = pre_terms |> term_or_list in
    let grouped_post_preconditions =
      let groups = Hashtbl.create 16 in
      let order = ref [] in
      entries
      |> List.iter (fun (_i, sc, _t) ->
             let pre =
               step_pre_terms_with_rec pre_vars_name sc |> term_and_list
             in
             let post =
               step_post_terms_with_rec post_vars_name sc |> term_and_list
             in
             if not (Hashtbl.mem groups post) then order := post :: !order;
             let previous =
               Hashtbl.find_opt groups post |> Option.value ~default:[]
             in
             Hashtbl.replace groups post (pre :: previous));
      List.rev !order
      |> List.map (fun post ->
             let pres = Hashtbl.find groups post |> List.rev in
             (term_or_list pres, post))
    in
    let post_body =
      grouped_post_preconditions
      |> List.map (fun (pre, post) -> term_implies pre post)
      |> term_and_list
    in
    let post_terms =
      grouped_post_preconditions |> List.map (fun (_pre, post) -> post)
    in
    let pre_text_bytes = String.length (string_of_term pre_term) in
    let post_text_bytes = String.length (string_of_term post_body) in
    ( pre_term,
      post_body,
      unique_term_count pre_terms,
      unique_term_count post_terms,
      List.length grouped_post_preconditions,
      pre_text_bytes,
      post_text_bytes,
      pre_text_bytes + post_text_bytes )
  in
  let group_entry_profile ((_, sc, _) as entry) =
    let pre_current =
      step_pre_terms_with_rec env.rec_name sc |> term_and_list
    in
    let pre_snapshot =
      step_pre_terms_with_rec pre_vars_name sc |> term_and_list
    in
    let post_snapshot =
      step_post_terms_with_rec post_vars_name sc |> term_and_list
    in
    let pre_current_s = string_of_term pre_current in
    let pre_snapshot_s = string_of_term pre_snapshot in
    let post_snapshot_s = string_of_term post_snapshot in
    ( entry,
      pre_current_s,
      String.length pre_current_s,
      pre_snapshot_s,
      String.length pre_snapshot_s,
      post_snapshot_s,
      String.length post_snapshot_s )
  in
  let profile_entry (entry, _pre_current_s, _pre_current_bytes,
      _pre_snapshot_s, _pre_snapshot_bytes, _post_snapshot_s,
      _post_snapshot_bytes) =
    entry
  in
  let profiled_group_cost profiles =
    let pre_bytes =
      profiles
      |> List.fold_left
           (fun acc (_entry, _pre_current_s, pre_current_bytes,
                _pre_snapshot_s, _pre_snapshot_bytes, _post_snapshot_s,
                _post_snapshot_bytes) ->
             acc + pre_current_bytes)
           0
    in
    let post_groups = Hashtbl.create 16 in
    profiles
    |> List.iter
         (fun (_entry, _pre_current_s, _pre_current_bytes, _pre_snapshot_s,
              pre_snapshot_bytes, post_snapshot_s, post_snapshot_bytes) ->
           let previous_pre_bytes, previous_post_bytes =
             Hashtbl.find_opt post_groups post_snapshot_s
             |> Option.value ~default:(0, post_snapshot_bytes)
           in
           Hashtbl.replace post_groups post_snapshot_s
             (previous_pre_bytes + pre_snapshot_bytes, previous_post_bytes));
    pre_bytes
    + (post_groups
      |> Hashtbl.to_seq_values
      |> Seq.fold_left
           (fun acc (pre_snapshot_bytes, post_snapshot_bytes) ->
             acc + pre_snapshot_bytes + post_snapshot_bytes)
           0)
  in
  let product_source_label (state : Ir.product_state) =
    Printf.sprintf "%s/a%d/g%d" state.prog_state state.assume_state_index
      state.guarantee_state_index
  in
  let record_group_metrics ~group_name ~emitted_as_group ~split_due_to_cost
      ~entries ~distinct_pre_count ~distinct_post_count ~post_implication_count
      ~pre_text_bytes ~post_text_bytes ~estimated_cost =
    let (_first_i, (first_sc : Why_contracts.step_contract_info), _first_t) =
      List.hd entries
    in
    External_timing.record_why3_product_group
      {
        group_name;
        node_name = runtime_view.node_name;
        transition_id = first_sc.step.transition_id;
        step_class = product_step_class_name first_sc.step.step_class;
        source_state = product_source_label first_sc.step.product_src;
        emitted_as_group;
        split_due_to_cost;
        edge_count = List.length entries;
        distinct_pre_count;
        distinct_post_count;
        post_implication_count;
        pre_text_bytes;
        post_text_bytes;
        estimated_cost;
        max_cost = why3_product_step_group_max_cost;
      }
  in
  let build_grouped_kernel_helper ~split_due_to_cost entries =
    let (first_i, (first_sc : Why_contracts.step_contract_info), first_t) =
      List.hd entries
    in
    let helper_name =
      ident (product_step_group_helper_name ~index:first_i first_sc.step)
    in
    let post_pred_name = helper_name.id_str ^ "_post" in
    let ( pre_term,
          post_body,
          distinct_pre_count,
          distinct_post_count,
          post_implication_count,
          pre_text_bytes,
          post_text_bytes,
          estimated_cost ) =
      grouped_kernel_terms entries
    in
    record_group_metrics ~group_name:helper_name.id_str ~emitted_as_group:true
      ~split_due_to_cost ~entries ~distinct_pre_count ~distinct_post_count
      ~post_implication_count ~pre_text_bytes ~post_text_bytes ~estimated_cost;
    let local_shared_decls =
      [ pre_term; post_body ]
      |> shared_formula_names_in_terms
      |> local_shared_formula_decls
    in
    let post_used_names = names_of_term post_body StringSet.empty in
    let post_input_binders =
      input_binders_without_vars
      |> List.filter (fun (_, id_opt, _, _) ->
             match id_opt with
             | None -> true
             | Some id -> StringSet.mem id.id_str post_used_names)
    in
    let post_pred_params =
      [ predicate_param_of_name pre_vars_name;
        predicate_param_of_name post_vars_name ]
      @ List.filter_map param_of_binder post_input_binders
    in
    let post_pred_decl =
      Ptree.Dlogic
        [
          {
            ld_loc = loc;
            ld_ident = ident post_pred_name;
            ld_params = post_pred_params;
            ld_type = None;
            ld_def = Some post_body;
          };
        ]
    in
    let post_call pre_snapshot_name =
      let pre_vars_term = mk_term (Tident (qid1 pre_snapshot_name)) in
      let vars_term = mk_term (Tident (qid1 env.rec_name)) in
      let args =
        [ pre_vars_term; vars_term ]
        @ List.filter_map binder_term post_input_binders
      in
      mk_term (Tidapp (qid1 post_pred_name, args))
    in
    let spc =
      {
        Ptree.sp_pre = [ pre_term ];
        sp_post = [];
        sp_xpost = [];
        sp_reads = [];
        sp_writes = [];
        sp_alias = [];
        sp_variant = [];
        sp_checkrw = false;
        sp_diverge = false;
        sp_partial = false;
      }
    in
    let pre_snapshot_name = "__pre_snapshot" in
    let snapshot_expr =
      env.rec_vars
      |> List.map (fun field_name -> (qid1 field_name, field env field_name))
      |> fun fields -> mk_expr (Erecord fields)
    in
    let helper_body =
      let proof_assert =
        mk_expr (Eassert (Expr.Assert, post_call pre_snapshot_name))
      in
      let body = seq_exprs [ compile_transition_body env [] first_t; proof_assert ] in
      mk_expr
        (Elet
           ( ident pre_snapshot_name,
             true,
             Expr.RKnone,
             snapshot_expr,
             body ))
    in
    let helper_inputs =
      helper_binders_without_unused_parameters inputs spc helper_body
    in
    let fn = helper_function helper_inputs spc helper_body in
    ( helper_name.id_str,
      local_shared_decls
      @ [ post_pred_decl; Ptree.Dlet (helper_name, false, Expr.RKnone, fn) ] )
  in
  let split_group_by_cost entries =
    if why3_product_step_group_max_cost <= 0 then [ entries ]
    else
      let profiles = List.map group_entry_profile entries in
      let rec loop chunks current_rev rest =
        match rest with
        | [] ->
            let chunks =
              match current_rev with
              | [] -> chunks
              | _ -> (List.rev current_rev |> List.map profile_entry) :: chunks
            in
            List.rev chunks
        | profile :: tail ->
            let candidate = List.rev (profile :: current_rev) in
            if current_rev <> []
               && profiled_group_cost candidate
                  > why3_product_step_group_max_cost
            then
              let chunk = List.rev current_rev |> List.map profile_entry in
              loop (chunk :: chunks) [ profile ] tail
            else loop chunks (profile :: current_rev) tail
      in
      loop [] [] profiles
  in
  let record_singleton_split_chunk ~split_due_to_cost i sc t =
    let entries = [ (i, sc, t) ] in
    let (_pre_term, _post_body, distinct_pre_count, distinct_post_count,
         post_implication_count, pre_text_bytes, post_text_bytes,
         estimated_cost) =
      grouped_kernel_terms entries
    in
    record_group_metrics
      ~group_name:(product_step_helper_name ~index:i sc.step)
      ~emitted_as_group:false ~split_due_to_cost ~entries ~distinct_pre_count
      ~distinct_post_count ~post_implication_count ~pre_text_bytes
      ~post_text_bytes ~estimated_cost
  in
  let group_kernel_helpers indexed_contracts =
    let indexed_transitions =
      indexed_contracts
      |> List.map (fun (i, (sc : Why_contracts.step_contract_info)) ->
             let t =
               Why_runtime_view.transition_of_product_step
                 ~simplify_runtime_actions:simplify_why3_runtime_actions sc.step
             in
             (i, sc, t))
    in
    let groups = Hashtbl.create 128 in
    let order = ref [] in
    let group_key (_i, (sc : Why_contracts.step_contract_info), t) =
      (sc.step.step_class, t)
    in
    List.iter
      (fun entry ->
        let key = group_key entry in
        if not (Hashtbl.mem groups key) then order := key :: !order;
        let previous = Hashtbl.find_opt groups key |> Option.value ~default:[] in
        Hashtbl.replace groups key (entry :: previous))
      indexed_transitions;
    List.rev !order
    |> List.concat_map (fun key ->
           let entries = Hashtbl.find groups key |> List.rev in
           let group_is_safe =
             match entries with
             | [] -> false
             | (_i, (sc : Why_contracts.step_contract_info), _t) :: _ ->
                 sc.step.step_class = Why_runtime_view.StepSafe
           in
           let groupable =
             group_why3_product_steps
             && List.length entries > 1
             (* Bad-guarantee groups are small and dominated by large negated
                exclusions; individual helpers are cheaper for SMT and keep
                proof granularity finer. *)
             && group_is_safe
             && List.for_all
                  (fun (_i, (sc : Why_contracts.step_contract_info), _t) ->
                    sc.local_cuts = [])
                  entries
           in
           if groupable then
             let chunks = split_group_by_cost entries in
             let split_due_to_cost = List.length chunks > 1 in
             chunks
             |> List.concat_map (function
                  | [] -> []
                  | [ (i, sc, t) ] ->
                      record_singleton_split_chunk ~split_due_to_cost i sc t;
                      [ build_individual_kernel_helper (i, sc) ]
                  | chunk ->
                      [ build_grouped_kernel_helper ~split_due_to_cost chunk ])
           else
             entries
             |> List.map (fun (i, sc, _t) -> build_individual_kernel_helper (i, sc)))
  in
  let kernel_step_helper_units =
    if not use_product_helper_contracts then []
    else step_contracts |> List.mapi (fun i sc -> (i, sc)) |> group_kernel_helpers
  in
  let kernel_step_helper_decls =
    List.concat_map (fun (_name, decls) -> decls) kernel_step_helper_units
  in
  let helper_decls =
    if use_product_helper_contracts then []
    else
    let mk_post t = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, t) ]) in
    List.map
      (fun (branch : Why_runtime_view.state_branch_view) ->
        let helper_name =
          ident (Printf.sprintf "step_from_%s" (String.lowercase_ascii branch.branch_state))
        in
        let helper_pre, helper_post =
          helper_spec_for_state branch.branch_state
        in
        let spc =
          {
            Ptree.sp_pre = helper_pre;
            sp_post = List.rev_map mk_post helper_post;
            sp_xpost = [];
            sp_reads = [];
            sp_writes = [];
            sp_alias = [];
            sp_variant = [];
            sp_checkrw = false;
            sp_diverge = false;
            sp_partial = false;
          }
        in
        let helper_body =
          compile_state_body env branch_entry_asserts branch_sticky_asserts branch.branch_state
            branch.branch_transitions
        in
        let helper_inputs =
          helper_binders_without_unused_warnings inputs spc helper_body
        in
        let fn =
          mk_expr
            (Efun
               ( helper_inputs,
                 None,
                 { pat_desc = Pwild; pat_loc = loc },
                 Ity.MaskVisible,
                 spc,
                 helper_body ))
        in
        Ptree.Dlet (helper_name, false, Expr.RKnone, fn))
      runtime_view.state_branches
  in
  let wrapper_body =
    if use_product_helper_contracts then ret_expr
    else
      let branches =
        List.map
          (fun (branch : Why_runtime_view.state_branch_view) ->
            let helper_name =
              Printf.sprintf "step_from_%s" (String.lowercase_ascii branch.branch_state)
            in
            let fallback_call =
              apply_expr (mk_expr (Eident (qid1 helper_name))) helper_args
            in
            ( { pat_desc = Papp (qid1 branch.branch_state, []); pat_loc = loc },
              fallback_call ))
          runtime_view.state_branches
      in
      let covered_states =
        runtime_view.state_branches
        |> List.map (fun (branch : Why_runtime_view.state_branch_view) -> branch.branch_state)
        |> List.sort_uniq String.compare
      in
      let all_states = List.sort_uniq String.compare runtime_view.control_states in
      let exhaustive = covered_states = all_states in
      mk_expr
        (Ematch
           ( field env "st",
             (if exhaustive then branches
              else
                branches
                @
                [
                  ( { pat_desc = Pwild; pat_loc = loc },
                    mk_expr (Esequence (full_step_body (), ret_expr)) );
                ]),
             [] ))
  in

  let step_decl =
    let wrapper_pre =
      if not use_product_helper_contracts then pre
      else pre
    in
    let spc =
      {
        Ptree.sp_pre = wrapper_pre;
        sp_post = [];
        sp_xpost = [];
        sp_reads = [];
        sp_writes = [];
        sp_alias = [];
        sp_variant = [];
        sp_checkrw = false;
        sp_diverge = false;
        sp_partial = false;
      }
    in
    let fun_body = wrapper_body in
    let fn =
      mk_expr
        (Efun
           ( inputs,
             None,
             { pat_desc = Pwild; pat_loc = loc },
             Ity.MaskVisible,
             spc,
             fun_body ))
    in
    Ptree.Dlet (ident "step", false, Expr.RKnone, fn)
  in

  let coherency_goal_decls =
    let goals = runtime_view.init_invariant_goals in
    if goals = [] then []
    else
      let init_guard =
        term_eq (term_of_var env "st") (mk_term (Tident (qid1 runtime_view.init_control_state)))
      in
      List.mapi
        (fun i (f : Ir.summary_formula) ->
          let base = compile_local_fo_formula_term env f.logic in
          let coherent_initial_state = term_and init_guard base in
          let vars_only =
            match inputs with vars_param :: _ -> [ vars_param ] | [] -> inputs
          in
          let quantified = mk_term (Tquant (Dterm.DTexists, vars_only, [], coherent_initial_state)) in
          Ptree.Dprop (Decl.Pgoal, ident (Printf.sprintf "coherency_goal_%d" (i + 1)), quantified))
        goals
  in
  let kernel_init_goal_decls =
    []
  in

  let common_decls =
    imports @ type_enum_decls @ function_decls @ [ type_state; type_vars ]
    @ getter_decls @ logic_getter_decls
  in
  if use_product_helper_contracts then
    let common_module =
      ( ident common_module_name,
        None,
        common_decls,
        { pre_labels = []; post_labels = [] } )
    in
    let init_modules =
      match coherency_goal_decls @ kernel_init_goal_decls with
      | [] -> []
      | init_goals ->
          [
            ( ident (module_name ^ "__init"),
              None,
              imports @ [ common_import ] @ init_goals,
              { pre_labels; post_labels } );
          ]
    in
    let helper_modules =
      kernel_step_helper_units
      |> List.map
           (fun (helper_name, decls) ->
             ( ident (module_name ^ "__" ^ helper_name),
               None,
               imports @ [ common_import ] @ decls,
               { pre_labels; post_labels } ))
    in
    common_module
    :: (List.rev !shared_pre_bundle_modules
       @ List.rev !shared_post_bundle_modules @ init_modules @ helper_modules)
  else
    let decls =
      common_decls @ shared_formula_decls @ kernel_step_helper_decls @ helper_decls
      @ [ step_decl ] @ coherency_goal_decls @ kernel_init_goal_decls
    in
    [ (ident module_name, None, decls, { pre_labels; post_labels }) ]

(** [compile_node_from_ir_node] helper value. *)

let compile_node_from_ir_node
    ?(share_why3_facts = true)
    ?(simplify_why3_formulas = true)
    ?(slice_why3_transition_bodies = true)
    ?(simplify_why3_runtime_actions = true)
    ?(deduplicate_why3_terms = true)
    ?(group_why3_product_steps = true)
    ?(why3_product_step_group_max_cost = 0)
    (node : Ir.node_ir) :
    (Ptree.ident * Ptree.qualid option * Ptree.decl list * spec_groups) list =
  compile_node_with_info ~share_why3_facts ~simplify_why3_formulas
    ~simplify_why3_runtime_actions ~deduplicate_why3_terms
    ~group_why3_product_steps ~why3_product_step_group_max_cost
    (prepare_ir_node ~simplify_why3_runtime_actions ~slice_why3_transition_bodies node)

(** [compile_program_ast_from_ir_nodes] helper value. *)

let compile_program_ast_from_ir_nodes
    ?(share_why3_facts = true)
    ?(simplify_why3_formulas = true)
    ?(slice_why3_transition_bodies = true)
    ?(simplify_why3_runtime_actions = true)
    ?(deduplicate_why3_terms = true)
    ?(group_why3_product_steps = true)
    ?(why3_product_step_group_max_cost = 0)
    (program_nodes : Ir.node_ir list) : program_ast =
  let modules =
    List.concat_map
      (compile_node_from_ir_node ~share_why3_facts ~simplify_why3_formulas
         ~slice_why3_transition_bodies ~simplify_why3_runtime_actions
         ~deduplicate_why3_terms ~group_why3_product_steps
         ~why3_product_step_group_max_cost)
      program_nodes
  in
  let mlw = Ptree.Modules (List.map (fun (a, _b, c, _) -> (a, c)) modules) in
  let module_info = List.map (fun (id, _, _, groups) -> (id.id_str, groups)) modules in
  { mlw; module_info }
