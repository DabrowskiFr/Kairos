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

[@@@ocaml.warning "-8-26-27-32-33"]

open Why3
open Ptree
open Ast
open Ast_builders
open Support
open Why_compile_expr

type env_info = Why_types.env_info

let is_mon_state_ctor (s : string) : bool =
  let len = String.length s in
  if len < 4 then false
  else
    String.sub s 0 3 = "Aut"
    && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub s 3 (len - 3))

let collect_ctor_iexpr (acc : ident list) (e : iexpr) : ident list =
  let add acc name = if List.mem name acc then acc else name :: acc in
  let rec go acc (e : iexpr) =
    match e.iexpr with
    | IVar name -> if is_mon_state_ctor name then add acc name else acc
    | ILitInt _ | ILitBool _ -> acc
    | IPar inner -> go acc inner
    | IUn (_, inner) -> go acc inner
    | IBin (_, a, b) -> go (go acc a) b
  in
  go acc e

let collect_ctor_hexpr (acc : ident list) (h : hexpr) : ident list =
  match h with HNow e -> collect_ctor_iexpr acc e | HPreK (e, _) -> collect_ctor_iexpr acc e

let rec collect_ctor_fo (acc : ident list) (f : fo) : ident list =
  match f with
  | FTrue | FFalse -> acc
  | FRel (h1, _, h2) -> collect_ctor_hexpr (collect_ctor_hexpr acc h1) h2
  | FPred (_, hs) -> List.fold_left collect_ctor_hexpr acc hs
  | FNot a -> collect_ctor_fo acc a
  | FAnd (a, b) | FOr (a, b) | FImp (a, b) -> collect_ctor_fo (collect_ctor_fo acc a) b

let rec collect_ctor_ltl (acc : ident list) (f : fo_ltl) : ident list =
  match f with
  | LTrue | LFalse -> acc
  | LAtom a -> collect_ctor_fo acc a
  | LNot a | LX a | LG a -> collect_ctor_ltl acc a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      collect_ctor_ltl (collect_ctor_ltl acc a) b

let rec collect_ctor_stmt (acc : ident list) (s : stmt) : ident list =
  match s.stmt with
  | SAssign (_, e) -> collect_ctor_iexpr acc e
  | SIf (c, tbr, fbr) ->
      let acc = collect_ctor_iexpr acc c in
      let acc = List.fold_left collect_ctor_stmt acc tbr in
      List.fold_left collect_ctor_stmt acc fbr
  | SMatch (e, branches, def) ->
      let acc = collect_ctor_iexpr acc e in
      let acc =
        List.fold_left (fun acc (_, body) -> List.fold_left collect_ctor_stmt acc body) acc branches
      in
      List.fold_left collect_ctor_stmt acc def
  | SCall (_, args, _) -> List.fold_left collect_ctor_iexpr acc args
  | SSkip -> acc

let collect_mon_state_ctors (n : Ast.node) : ident list =
  let n = n in
  let acc = ref [] in
  List.iter (fun f -> acc := collect_ctor_ltl !acc f) (n.assumes @ n.guarantees);
  List.iter (fun inv -> acc := collect_ctor_hexpr !acc inv.inv_expr) n.attrs.invariants_user;
  List.iter (fun inv -> acc := collect_ctor_fo !acc inv.formula) n.attrs.invariants_state_rel;
  List.iter (fun g -> acc := collect_ctor_fo !acc g.value) n.attrs.coherency_goals;
  List.iter
    (fun (t : transition) ->
      List.iter
        (fun f -> acc := collect_ctor_fo !acc f)
        (Ast_provenance.values t.requires @ Ast_provenance.values t.ensures))
    n.trans;
  List.iter
    (fun (t : transition) ->
      acc := List.fold_left collect_ctor_stmt !acc t.attrs.ghost;
      acc := List.fold_left collect_ctor_stmt !acc t.body;
      acc := List.fold_left collect_ctor_stmt !acc t.attrs.instrumentation)
    n.trans;
  let ctor_index s = try int_of_string (String.sub s 3 (String.length s - 3)) with _ -> 0 in
  List.sort (fun a b -> compare (ctor_index a) (ctor_index b)) !acc

let prepare_node ~(prefix_fields : bool) ~(nodes : Ast.node list) (n : Ast.node) :
    Why_types.env_info =
  let n_obc = n in
  let nodes = nodes in
  let n = n in
  let module_name = module_name_of_node n.nname in
  let is_initial_only = function LG _ -> false | _ -> true in
  let instance_imports =
    n.instances
    |> List.map (fun (_, node_name) -> module_name_of_node node_name)
    |> List.sort_uniq String.compare
    |> List.map (fun name -> Ptree.Duseimport (loc, false, [ (qid1 name, None) ]))
  in
  let imports =
    [
      Ptree.Duseimport (loc, false, [ (qid1 "int.Int", None) ]);
      Ptree.Duseimport (loc, false, [ (qid1 "array.Array", None) ]);
    ]
    @ instance_imports
  in
  let mon_state_ctors = collect_mon_state_ctors n_obc in
  let type_mon_state =
    match mon_state_ctors with
    | [] -> []
    | ctors ->
        [
          Ptree.Dtype
            [
              {
                td_loc = loc;
                td_ident = ident "aut_state";
                td_params = [];
                td_vis = Public;
                td_mut = false;
                td_inv = [];
                td_wit = None;
                td_def = TDalgebraic (List.map (fun s -> (loc, ident s, [])) ctors);
              };
            ];
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
          td_def = TDalgebraic (List.map (fun s -> (loc, ident s, [])) n.states);
        };
      ]
  in
  let default_custom_init = function
    | "aut_state" -> begin
        match mon_state_ctors with first :: _ -> Some (mk_var first) | [] -> None
      end
    | _ -> None
  in
  let init_for_var =
    let table = List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs) in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> mk_bool false
      | Some TInt -> mk_int 0
      | Some TReal -> mk_int 0
      | Some (TCustom name) -> Option.value (default_custom_init name) ~default:(mk_int 0)
      | None -> mk_int 0
  in
  let pre_k_map = Collect.build_pre_k_infos n in
  let pre_k_infos = List.map snd pre_k_map in
  let has_initial_only_contracts = List.exists is_initial_only (n.assumes @ n.guarantees) in
  let needs_step_count = false in
  let needs_first_step = false in
  let inv_links = List.map (fun inv -> (inv.inv_expr, inv.inv_id)) n.attrs.invariants_user in
  let field_prefix = if prefix_fields then prefix_for_node n.nname else "" in
  let input_names = Ast_utils.input_names_of_node n in
  let base_vars =
    ("st" :: List.map (fun v -> v.vname) (n.locals @ n.outputs)) @ List.map fst n.instances
  in
  let hexpr_needs_old (_h : hexpr) : bool = false in
  let var_map = List.map (fun name -> (name, field_prefix ^ name)) base_vars in
  let env =
    {
      rec_name = "vars";
      rec_vars = base_vars;
      var_map;
      links = inv_links;
      pre_k = pre_k_map;
      inst_map = n.instances;
      inputs = input_names;
    }
  in
  let instance_fields =
    List.map
      (fun (inst_name, node_name) ->
        let mod_name = module_name_of_node node_name in
        {
          f_loc = loc;
          f_ident = ident (rec_var_name env inst_name);
          f_pty = Ptree.PTtyapp (qdot (qid1 mod_name) "vars", []);
          f_mutable = true;
          f_ghost = false;
        })
      n.instances
  in
  let is_ghost_local name =
    (String.length name >= 7 && String.sub name 0 7 = "__atom_")
    || (String.length name >= 5 && String.sub name 0 5 = "atom_")
    || (String.length name >= 6 && String.sub name 0 6 = "__aut_")
    || (String.length name >= 6 && String.sub name 0 6 = "__pre_")
  in
  let local_fields =
    List.map
      (fun v ->
        {
          f_loc = loc;
          f_ident = ident (rec_var_name env v.vname);
          f_pty = default_pty v.vty;
          f_mutable = true;
          f_ghost = is_ghost_local v.vname;
        })
      n.locals
  in
  let output_fields =
    List.map
      (fun v ->
        {
          f_loc = loc;
          f_ident = ident (rec_var_name env v.vname);
          f_pty = default_pty v.vty;
          f_mutable = true;
          f_ghost = false;
        })
      n.outputs
  in
  let fields : Ptree.field list =
    {
      f_loc = loc;
      f_ident = ident (rec_var_name env "st");
      f_pty = Ptree.PTtyapp (qid1 "state", []);
      f_mutable = true;
      f_ghost = false;
    }
    :: (local_fields @ output_fields)
    @ instance_fields @ []
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
  let field_qid name = qid1 (rec_var_name env name) in
  let empty_spec =
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
  in
  let any_expr_for_type ty =
    let pty = default_pty ty in
    let pat = { pat_desc = Pwild; pat_loc = loc } in
    mk_expr (Eany ([], Expr.RKnone, Some pty, pat, Ity.MaskVisible, empty_spec))
  in
  let default_expr_for_type = function
    | TInt -> mk_expr (Econst (Constant.int_const BigInt.zero))
    | TBool -> mk_expr Efalse
    | TReal ->
        mk_expr
          (Econst (Constant.real_const_from_string ~radix:10 ~neg:false ~int:"0" ~frac:"" ~exp:None))
    | TCustom name -> begin
        match default_custom_init name with
        | Some e -> begin
            match e.iexpr with
            | IVar id -> mk_expr (Eident (qid1 id))
            | _ -> mk_expr (Econst (Constant.int_const BigInt.zero))
          end
        | _ -> mk_expr (Econst (Constant.int_const BigInt.zero))
      end
  in
  let init_expr_for_name vname vty =
    let should_init = vname = "st" || vname = "__aut_state" || vname = "acc" in
    if should_init then default_expr_for_type vty else any_expr_for_type vty
  in
  let vars_param = (loc, Some (ident "vars"), false, Some (Ptree.PTtyapp (qid1 "vars", []))) in
  let inputs =
    match n.inputs with
    | [] -> [ vars_param ]
    | _ ->
        vars_param
        :: List.map (fun v -> (loc, Some (ident v.vname), false, Some (default_pty v.vty))) n.inputs
  in
  let has_ghost_updates = false in
  let ghost_updates = mk_expr (Etuple []) in
  let ret_expr = mk_expr (Etuple []) in
  let node = n in
  {
    node;
    module_name;
    imports;
    type_mon_state;
    type_state;
    type_vars;
    env;
    inputs;
    ret_expr;
    ghost_updates;
    has_ghost_updates;
    pre_k_map;
    pre_k_infos;
    needs_step_count;
    needs_first_step;
    has_initial_only_contracts;
    hexpr_needs_old;
    input_names;
    mon_state_ctors;
    init_for_var;
  }
