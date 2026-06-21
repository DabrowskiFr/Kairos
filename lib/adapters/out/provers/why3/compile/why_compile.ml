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

module StringSet = Set.Make (String)

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

(** [empty_spec] helper value. *)

let empty_spec () : Ptree.spec =
  {
    Ptree.sp_pre = [];
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

(** [term_and] helper value. *)

let term_and (a : Ptree.term) (b : Ptree.term) : Ptree.term = mk_term (Tbinnop (a, Dterm.DTand, b))


(** [binder_expr] helper value. *)

let binder_expr ((_, id_opt, _, _) : Ptree.binder) : Ptree.expr =
  match id_opt with Some id -> mk_expr (Eident (qid1 id.id_str)) | None -> mk_expr (Etuple [])

let binder_term ((_, id_opt, _, _) : Ptree.binder) : Ptree.term option =
  Option.map (fun id -> mk_term (Tident (qid1 id.id_str))) id_opt

let param_of_binder ((bloc, id_opt, ghost, pty_opt) : Ptree.binder) : Ptree.param option =
  Option.map (fun pty -> (bloc, id_opt, ghost, pty)) pty_opt

let term_and_list (terms : Ptree.term list) : Ptree.term =
  match terms with
  | [] -> mk_term Ttrue
  | [ term ] -> term
  | first :: rest -> List.fold_left term_and first rest

let rec names_of_qualid (qid : Ptree.qualid) (acc : StringSet.t) : StringSet.t =
  match qid with
  | Qident id -> StringSet.add id.id_str acc
  | Qdot (parent, id) -> StringSet.add id.id_str (names_of_qualid parent acc)

let rec names_of_term (term : Ptree.term) (acc : StringSet.t) : StringSet.t =
  match term.term_desc with
  | Ttrue | Tfalse | Tconst _ -> acc
  | Tident qid | Tasref qid -> names_of_qualid qid acc
  | Tidapp (qid, terms) ->
      List.fold_left (fun acc term -> names_of_term term acc) (names_of_qualid qid acc) terms
  | Tapply (fn, arg) ->
      names_of_term arg (names_of_term fn acc)
  | Tinfix (lhs, _, rhs)
  | Tinnfix (lhs, _, rhs)
  | Tbinop (lhs, _, rhs)
  | Tbinnop (lhs, _, rhs) ->
      names_of_term rhs (names_of_term lhs acc)
  | Tnot inner | Tcast (inner, _) | Tscope (_, inner) | Tat (inner, _) | Tattr (_, inner) ->
      names_of_term inner acc
  | Tif (cond, t_then, t_else) ->
      names_of_term t_else (names_of_term t_then (names_of_term cond acc))
  | Tquant (_, _, triggers, body) ->
      let acc =
        List.fold_left
          (fun acc trigger -> List.fold_left (fun acc term -> names_of_term term acc) acc trigger)
          acc triggers
      in
      names_of_term body acc
  | Teps (_, _, body) -> names_of_term body acc
  | Tlet (_, value, body) -> names_of_term body (names_of_term value acc)
  | Tcase (scrutinee, branches) ->
      List.fold_left
        (fun acc (_pattern, body) -> names_of_term body acc)
        (names_of_term scrutinee acc) branches
  | Ttuple terms ->
      List.fold_left (fun acc term -> names_of_term term acc) acc terms
  | Trecord fields ->
      List.fold_left (fun acc (_field, term) -> names_of_term term acc) acc fields
  | Tupdate (base, fields) ->
      List.fold_left
        (fun acc (_field, term) -> names_of_term term acc)
        (names_of_term base acc) fields

let names_of_variant (variant : Ptree.variant) (acc : StringSet.t) : StringSet.t =
  List.fold_left (fun acc (term, _rel) -> names_of_term term acc) acc variant

let rec term_has_old (term : Ptree.term) : bool =
  match term.term_desc with
  | Tapply (fn, arg) -> begin
      match fn.term_desc with
      | Tident qid when String.equal (string_of_qid qid) "old" -> true
      | _ -> term_has_old fn || term_has_old arg
    end
  | Tat (_, id) when String.equal id.id_str "old" -> true
  | Tinfix (lhs, _, rhs)
  | Tinnfix (lhs, _, rhs)
  | Tbinop (lhs, _, rhs)
  | Tbinnop (lhs, _, rhs) ->
      term_has_old lhs || term_has_old rhs
  | Tnot inner | Tcast (inner, _) | Tscope (_, inner) | Tat (inner, _) | Tattr (_, inner) ->
      term_has_old inner
  | Tif (cond, t_then, t_else) ->
      term_has_old cond || term_has_old t_then || term_has_old t_else
  | Tquant (_, _, triggers, body) ->
      List.exists (List.exists term_has_old) triggers || term_has_old body
  | Teps (_, _, body) -> term_has_old body
  | Tlet (_, value, body) -> term_has_old value || term_has_old body
  | Tcase (scrutinee, branches) ->
      term_has_old scrutinee
      || List.exists (fun (_pattern, body) -> term_has_old body) branches
  | Tidapp (_, terms) | Ttuple terms -> List.exists term_has_old terms
  | Trecord fields -> List.exists (fun (_field, term) -> term_has_old term) fields
  | Tupdate (base, fields) ->
      term_has_old base || List.exists (fun (_field, term) -> term_has_old term) fields
  | Ttrue | Tfalse | Tconst _ | Tident _ | Tasref _ -> false

let names_of_spec (spc : Ptree.spec) (acc : StringSet.t) : StringSet.t =
  let acc = List.fold_left (fun acc term -> names_of_term term acc) acc spc.sp_pre in
  let acc =
    List.fold_left
      (fun acc (_loc, posts) ->
        List.fold_left (fun acc (_pat, term) -> names_of_term term acc) acc posts)
      acc spc.sp_post
  in
  let acc =
    List.fold_left
      (fun acc (_loc, posts) ->
        List.fold_left
          (fun acc (_qid, post_opt) ->
            match post_opt with
            | None -> acc
            | Some (_pat, term) -> names_of_term term acc)
          acc posts)
      acc spc.sp_xpost
  in
  let acc = List.fold_left (fun acc term -> names_of_term term acc) acc spc.sp_writes in
  let acc =
    List.fold_left
      (fun acc (lhs, rhs) -> names_of_term rhs (names_of_term lhs acc))
      acc spc.sp_alias
  in
  names_of_variant spc.sp_variant acc

let rec names_of_expr (expr : Ptree.expr) (acc : StringSet.t) : StringSet.t =
  match expr.expr_desc with
  | Eref | Etrue | Efalse | Econst _ | Eabsurd -> acc
  | Eident qid | Easref qid | Eidpur qid -> names_of_qualid qid acc
  | Eidapp (qid, args) ->
      List.fold_left (fun acc expr -> names_of_expr expr acc) (names_of_qualid qid acc) args
  | Eapply (fn, arg) | Einfix (fn, _, arg) | Einnfix (fn, _, arg) ->
      names_of_expr arg (names_of_expr fn acc)
  | Elet (_, _, _, value, body) ->
      names_of_expr body (names_of_expr value acc)
  | Erec (defs, body) ->
      let acc =
        List.fold_left
          (fun acc (_id, _ghost, _kind, _binders, _pty, _pat, _mask, spc, body) ->
            names_of_expr body (names_of_spec spc acc))
          acc defs
      in
      names_of_expr body acc
  | Efun (_binders, _pty, _pat, _mask, spc, body) ->
      names_of_expr body (names_of_spec spc acc)
  | Eany (_params, _kind, _pty, _pat, _mask, spc) ->
      names_of_spec spc acc
  | Etuple exprs ->
      List.fold_left (fun acc expr -> names_of_expr expr acc) acc exprs
  | Erecord fields ->
      List.fold_left (fun acc (_field, expr) -> names_of_expr expr acc) acc fields
  | Eupdate (base, fields) ->
      List.fold_left
        (fun acc (_field, expr) -> names_of_expr expr acc)
        (names_of_expr base acc) fields
  | Eassign assigns ->
      List.fold_left
        (fun acc (lhs, _field, rhs) -> names_of_expr rhs (names_of_expr lhs acc))
        acc assigns
  | Esequence (first, second)
  | Eand (first, second)
  | Eor (first, second) ->
      names_of_expr second (names_of_expr first acc)
  | Eif (cond, t_then, t_else) ->
      names_of_expr t_else (names_of_expr t_then (names_of_expr cond acc))
  | Ewhile (cond, invariant, variant, body) ->
      let acc = List.fold_left (fun acc term -> names_of_term term acc) acc invariant in
      names_of_expr body (names_of_variant variant (names_of_expr cond acc))
  | Enot inner | Ecast (inner, _) | Eghost inner | Eattr (_, inner) | Elabel (_, inner)
  | Escope (_, inner) ->
      names_of_expr inner acc
  | Ematch (scrutinee, branches, exn_branches) ->
      let acc =
        List.fold_left
          (fun acc (_pat, body) -> names_of_expr body acc)
          (names_of_expr scrutinee acc) branches
      in
      List.fold_left
        (fun acc (_qid, _pattern_opt, body) -> names_of_expr body acc)
        acc exn_branches
  | Epure term | Eassert (_, term) -> names_of_term term acc
  | Eraise (_qid, expr_opt) -> Option.fold ~none:acc ~some:(fun expr -> names_of_expr expr acc) expr_opt
  | Eexn (_, _, _, body) | Eoptexn (_, _, body) -> names_of_expr body acc
  | Efor (_, start, _dir, stop, invariant, body) ->
      let acc = List.fold_left (fun acc term -> names_of_term term acc) acc invariant in
      names_of_expr body (names_of_expr stop (names_of_expr start acc))

let mark_unused_binders (used : StringSet.t) (binders : Ptree.binder list) : Ptree.binder list =
  let should_mark_unused id =
    (not (StringSet.mem id.id_str used)) && not (String.starts_with ~prefix:"_" id.id_str)
  in
  List.map
    (fun (bloc, id_opt, ghost, pty_opt) ->
      match id_opt with
      | Some id when should_mark_unused id ->
          (bloc, Some (ident ("_" ^ id.id_str)), ghost, pty_opt)
      | _ -> (bloc, id_opt, ghost, pty_opt))
    binders

let helper_binders_without_unused_warnings (binders : Ptree.binder list) (spc : Ptree.spec)
    (body : Ptree.expr) : Ptree.binder list =
  let used = names_of_expr body (names_of_spec spc StringSet.empty) in
  mark_unused_binders used binders

let helper_binders_without_unused_parameters (binders : Ptree.binder list) (spc : Ptree.spec)
    (body : Ptree.expr) : Ptree.binder list =
  let used = names_of_expr body (names_of_spec spc StringSet.empty) in
  List.filter
    (fun (_, id_opt, _, _) ->
      match id_opt with
      | None -> true
      | Some id -> StringSet.mem id.id_str used)
    binders

let balance_boolean_hexpr (formula : Core_syntax.hexpr) : Core_syntax.hexpr =
  let build_balanced op formulas =
    match formulas with
    | [] -> invalid_arg "balance_boolean_hexpr: empty boolean formula list"
    | [ formula ] -> formula
    | _ ->
        let arr = Array.of_list formulas in
        let rec build lo hi =
          if hi - lo = 1 then arr.(lo)
          else
            let mid = lo + ((hi - lo) / 2) in
            Core_syntax_builders.mk_hexpr (HBin (op, build lo mid, build mid hi))
        in
        build 0 (Array.length arr)
  in
  let rec flatten op acc h =
    match h.hexpr with
    | HBin (op', a, b) when op = op' -> flatten op (flatten op acc b) a
    | _ -> h :: acc
  in
  let rec normalize h =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> h
    | HUn (op, inner) -> Core_syntax_builders.with_hexpr_desc h (HUn (op, normalize inner))
    | HPred (id, hs) -> Core_syntax_builders.with_hexpr_desc h (HPred (id, List.map normalize hs))
    | HFunCall (fn, hs) ->
        Core_syntax_builders.with_hexpr_desc h (HFunCall (fn, List.map normalize hs))
    | HBin ((And | Or as op), _, _) ->
        flatten op [] h |> List.rev |> List.map normalize |> build_balanced op
    | HBin (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h (HBin (op, normalize a, normalize b))
    | HCmp (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h (HCmp (op, normalize a, normalize b))
  in
  normalize formula

(** [logic_getter_decl] helper value. *)

let logic_getter_decl ~(env : Why_compile_expr.env) (vname : ident) (vty : ty) : Ptree.decl =
  let field_name = vname in
  let getter_name = ident ("logic_" ^ field_name) in
  let param : Ptree.param = (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", [])) in
  let body = term_of_var { env with rec_name = "self" } field_name in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = getter_name;
        ld_params = [ param ];
        ld_type = Some (default_pty vty);
        ld_def = Some body;
      };
    ]

(** [logic_bool_pred_decl] helper value. *)

let logic_bool_pred_decl ~(env : Why_compile_expr.env) ~(input_ports : Why_runtime_view.port_view list)
    ~(name : string) ~(formula : Core_syntax.hexpr) : Ptree.decl =
  let env = { env with rec_name = "self" } in
  let self_param : Ptree.param = (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", [])) in
  let input_params =
    List.map
      (fun (p : Why_runtime_view.port_view) ->
        (loc, Some (ident p.port_name), false, default_pty p.port_type))
      input_ports
  in
  let body = Why_compile_expr.compile_local_fo_formula_term env (balance_boolean_hexpr formula) in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = self_param :: input_params;
        ld_type = None;
        ld_def = Some body;
      };
    ]

let logic_bool_pred_decl_with_params ~(env : Why_compile_expr.env)
    ~(params : (ident * Ptree.pty) list) ~(name : string) ~(formula : Core_syntax.hexpr) :
    Ptree.decl =
  let env = { env with rec_name = "self" } in
  let self_param : Ptree.param = (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", [])) in
  let params =
    List.map (fun (name, pty) -> (loc, Some (ident name), false, pty)) params
  in
  let body = Why_compile_expr.compile_local_fo_formula_term env (balance_boolean_hexpr formula) in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = self_param :: params;
        ld_type = None;
        ld_def = Some body;
      };
    ]

let logic_bool_pred_decl_with_body ~use_self
    ~(params : (ident * Ptree.pty) list) ~(name : string) ~(body : Ptree.term) :
    Ptree.decl =
  let self_param : Ptree.param = (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", [])) in
  let params =
    List.map (fun (name, pty) -> (loc, Some (ident name), false, pty)) params
  in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = (if use_self then self_param :: params else params);
        ld_type = None;
        ld_def = Some body;
      };
    ]

let rec hexpr_size (h : Core_syntax.hexpr) : int =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> 1
  | HUn (_, inner) -> 1 + hexpr_size inner
  | HPred (_, hs) | HFunCall (_, hs) ->
      1 + List.fold_left (fun acc h -> acc + hexpr_size h) 0 hs
  | HBin (_, a, b) | HCmp (_, a, b) -> 1 + hexpr_size a + hexpr_size b

let rec vars_of_hexpr (acc : StringSet.t) (h : Core_syntax.hexpr) : StringSet.t =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ -> acc
  | HVar name | HPreK (name, _) -> StringSet.add name acc
  | HUn (_, inner) -> vars_of_hexpr acc inner
  | HPred (_, hs) | HFunCall (_, hs) -> List.fold_left vars_of_hexpr acc hs
  | HBin (_, a, b) | HCmp (_, a, b) -> vars_of_hexpr (vars_of_hexpr acc a) b

(** [port_view_to_vdecl] helper value. *)

let port_view_to_vdecl (p : Why_runtime_view.port_view) : vdecl =
  { vname = p.port_name; vty = p.port_type }

(** [compile_pure_function_decl] translates a source-level pure function into a
    WhyML function with pre/postconditions. *)
let is_definition_postcondition (body : Core_syntax.hexpr) (ens : Core_syntax.hexpr) : bool =
  match ens.hexpr with
  | HCmp (REq, { hexpr = HVar "result"; _ }, rhs)
  | HCmp (REq, rhs, { hexpr = HVar "result"; _ }) ->
      Core_fo_simplifier.simplify rhs = Core_fo_simplifier.simplify body
  | _ -> false

let compile_pure_function_decl (f : pure_function_decl) : Ptree.decl =
  let env = { rec_name = ""; rec_vars = []; links = [] } in
  let binders =
    List.map
      (fun (v : vdecl) -> (loc, Some (ident v.vname), false, Some (default_pty v.vty)))
      f.function_params
  in
  let body_hexpr = Core_syntax_builders.hexpr_of_expr f.function_body in
  let drop_definition_contract =
    f.function_requires = []
    && List.for_all (is_definition_postcondition body_hexpr) f.function_ensures
  in
  let mk_post t =
    (loc, [ ({ pat_desc = Pvar (ident "result"); pat_loc = loc }, t) ])
  in
  let spc =
    if drop_definition_contract then empty_spec ()
    else
      {
        Ptree.sp_pre = List.map (compile_local_fo_formula_term env) f.function_requires;
        sp_post =
          List.map (fun ens -> mk_post (compile_local_fo_formula_term env ens)) f.function_ensures;
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
  let fn =
    mk_expr
      (Efun
         ( binders,
           Some (default_pty f.function_return),
           { pat_desc = Pwild; pat_loc = loc },
           Ity.MaskVisible,
           spc,
           compile_expr env f.function_body ))
  in
  Ptree.Dlet (ident f.function_name, false, Expr.RKfunc, fn)

(* Shared compilation core: all node-specific data is read from [info.runtime_view].
   The active path builds [info] from the IR via [prepare_ir_node]. *)
(** [compile_node_with_info] helper value. *)

let compile_node_with_info ?kernel_ir
    ?(share_why3_facts = true)
    ?(simplify_why3_formulas = true)
    ?(simplify_why3_runtime_actions = true)
    ?(deduplicate_why3_terms = true)
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
  let phase_case_logic_decls =
    match kernel_ir with
    | None -> []
    | Some (ir : Proof_kernel_types.node_ir) ->
        let seen = Hashtbl.create 32 in
        let add_decl acc name formula =
          if Hashtbl.mem seen name then acc
          else (
            Hashtbl.add seen name ();
            logic_bool_pred_decl ~env ~input_ports:runtime_view.inputs ~name ~formula :: acc)
        in
        ir.eliminated_generated_clauses
        |> List.fold_left
             (fun acc (clause : Proof_kernel_types.generated_clause_ir) ->
               match (clause.origin, clause.anchor) with
               | Proof_kernel_types.OriginSourceProductSummary, ClauseAnchorProductState st -> begin
                   let phase_formula =
                     clause.conclusions
                     |> List.find_map (fun (fact : Proof_kernel_types.clause_fact_ir) ->
                            match (fact.time, fact.desc) with
                            | Proof_kernel_types.CurrentTick, Proof_kernel_types.FactPhaseFormula phase_formula ->
                                Some phase_formula
                            | _ -> None)
                   in
                   match phase_formula with
                   | None -> acc
                   | Some phase_formula ->
                       add_decl acc
                         (Proof_kernel_naming.phase_state_case_name ~prog_state:st.prog_state
                            ~guarantee_state:st.guarantee_state_index)
                         phase_formula
                 end
               | _ -> acc)
             []
        |> List.rev
  in
  let shared_formula_params =
    inputs
    |> List.filter_map (fun (_, id_opt, _, pty_opt) ->
           match (id_opt, pty_opt) with
           | Some id, Some pty when not (String.equal id.id_str env.rec_name) -> Some (id.id_str, pty)
           | _ -> None)
  in
  let formula_key (formula : Core_syntax.hexpr) =
    let binop_key = function
      | Add -> "add"
      | Sub -> "sub"
      | Mul -> "mul"
      | Div -> "div"
      | And -> "and"
      | Or -> "or"
    in
    let unop_key = function Neg -> "neg" | Not -> "not" in
    let relop_key = function
      | REq -> "eq"
      | RNeq -> "neq"
      | RLt -> "lt"
      | RLe -> "le"
      | RGt -> "gt"
      | RGe -> "ge"
    in
    let rec go h =
      match h.hexpr with
      | HLitInt n -> "i:" ^ string_of_int n
      | HLitBool b -> "b:" ^ string_of_bool b
      | HLitEnum c -> "e:" ^ c
      | HVar v -> "v:" ^ v
      | HPreK (v, k) -> "pre:" ^ v ^ ":" ^ string_of_int k
      | HPred (id, hs) -> "pred:" ^ id ^ "(" ^ String.concat "," (List.map go hs) ^ ")"
      | HFunCall (fn, hs) ->
          "fun:" ^ fn ^ "(" ^ String.concat "," (List.map go hs) ^ ")"
      | HUn (op, inner) -> "un:" ^ unop_key op ^ "(" ^ go inner ^ ")"
      | HBin (op, a, b) ->
          "bin:" ^ binop_key op ^ "(" ^ go a ^ "," ^ go b ^ ")"
      | HCmp (op, a, b) ->
          "cmp:" ^ relop_key op ^ "(" ^ go a ^ "," ^ go b ^ ")"
    in
    go formula
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
        add_summary_formulas ~scope pc.ensures;
        add_summary_formulas ~scope pc.forbidden)
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
  let local_shared_formula_decls names =
    let closure = shared_formula_closure names in
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
          modules :=
            ( ident bundle_module_name,
              None,
              imports @ [ common_import; decl ],
              { pre_labels = []; post_labels = [] } )
            :: !modules;
          (bundle_module_name, name)
    in
    (import_module bundle_module_name, mk_term (Tidapp (qid1 name, args)))
  in
  let shared_post_bundle_table : (string, string * string) Hashtbl.t = Hashtbl.create 128 in
  let shared_post_bundle_modules = ref [] in
  let shared_post_bundle_call =
    shared_bundle_call ~module_suffix:"Post" ~predicate_prefix:"shared_post_bundle"
      ~table:shared_post_bundle_table ~modules:shared_post_bundle_modules
  in
  let prepared_step_helper_units =
    if not use_product_helper_contracts then []
    else
      step_contracts
      |> List.mapi (fun i sc -> (i, sc))
      |> List.map (fun (i, (sc : Why_contracts.step_contract_info)) ->
             let t =
               Why_runtime_view.transition_of_product_step
                 ~simplify_runtime_actions:simplify_why3_runtime_actions sc.step
             in
             let helper_name = ident (step_helper_name ~index:i sc) in
             let state_guard =
               term_eq (term_of_var env "st") (mk_term (Tident (qid1 t.src_state)))
             in
             let raw_pre_terms = state_guard :: sc.pre in
             let raw_post_terms = sc.forbidden @ sc.post in
             let bundle_post_terms =
               List.length raw_post_terms > 1
               && not (List.exists term_has_old raw_post_terms)
             in
             (i, sc, t, helper_name, raw_pre_terms, raw_post_terms, bundle_post_terms))
  in
  let kernel_step_helper_units =
    prepared_step_helper_units
    |> List.map
         (fun ( i,
                (sc : Why_contracts.step_contract_info),
                t,
                helper_name,
                raw_pre_terms,
                raw_post_terms,
                bundle_post_terms ) ->
             let mk_post term = (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, term) ]) in
             let pre_bundle_decls, pre_term =
               let pre_decl, call =
                 predicate_bundle_decl_and_call
                   ~name:(helper_name.id_str ^ "_pre")
                   raw_pre_terms
               in
               ([ pre_decl ], call)
             in
             let post_bundle_decls, post_terms =
               if not bundle_post_terms then ([], raw_post_terms)
               else
                 let post_import, call = shared_post_bundle_call raw_post_terms in
                 ([ post_import ], [ call ])
             in
             let spc =
               {
                 Ptree.sp_pre = [ pre_term ];
                 (* Helper contracts may use shared predicates to control
                    global text size.  Selected helper-local cuts are emitted
                    unfolded in the body, as assertions, so they add proof
                    obligations instead of weakening the postcondition. *)
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
             let helper_body =
               seq_exprs (compile_transition_body env [] t :: local_cut_asserts)
             in
             let helper_inputs =
               helper_binders_without_unused_parameters inputs spc helper_body
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
             ( i,
               sc,
               helper_name.id_str,
               pre_bundle_decls @ post_bundle_decls
               @ [ Ptree.Dlet (helper_name, false, Expr.RKnone, fn) ] ))
  in
  let kernel_step_helper_decls =
    List.concat_map (fun (_i, _sc, _name, decls) -> decls) kernel_step_helper_units
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
    @ getter_decls @ logic_getter_decls @ phase_case_logic_decls
  in
  if use_product_helper_contracts then
    let common_module =
      ( ident common_module_name,
        None,
        common_decls @ shared_formula_decls,
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
           (fun
             ( _i,
               (_sc : Why_contracts.step_contract_info),
               helper_name,
               decls ) ->
             ( ident (module_name ^ "__" ^ helper_name),
               None,
               imports @ [ common_import ] @ decls,
               { pre_labels; post_labels } ))
    in
    common_module
    :: (List.rev !shared_post_bundle_modules @ init_modules @ helper_modules)
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
    (node : Ir.node_ir) :
    (Ptree.ident * Ptree.qualid option * Ptree.decl list * spec_groups) list =
  compile_node_with_info ~share_why3_facts ~simplify_why3_formulas
    ~simplify_why3_runtime_actions ~deduplicate_why3_terms
    (prepare_ir_node ~simplify_why3_runtime_actions ~slice_why3_transition_bodies node)

(** [compile_program_ast_from_ir_nodes] helper value. *)

let compile_program_ast_from_ir_nodes
    ?(share_why3_facts = true)
    ?(simplify_why3_formulas = true)
    ?(slice_why3_transition_bodies = true)
    ?(simplify_why3_runtime_actions = true)
    ?(deduplicate_why3_terms = true)
    (program_nodes : Ir.node_ir list) : program_ast =
  let modules =
    List.concat_map
      (compile_node_from_ir_node ~share_why3_facts ~simplify_why3_formulas
         ~slice_why3_transition_bodies ~simplify_why3_runtime_actions
         ~deduplicate_why3_terms)
      program_nodes
  in
  let mlw = Ptree.Modules (List.map (fun (a, _b, c, _) -> (a, c)) modules) in
  let module_info = List.map (fun (id, _, _, groups) -> (id.id_str, groups)) modules in
  { mlw; module_info }
