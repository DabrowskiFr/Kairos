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
open Generated_names
open Temporal_support
open Ast_pretty
open Why_term_support
open Why_compile_expr

type env_info = Why_types.env_info

let prepare_runtime_view ~(prefix_fields : bool)
    ~(pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list)
    (runtime : Why_runtime_view.t) : Why_types.env_info =
  let n = Why_runtime_view.to_ast_node runtime in
  let n_obc = n in
  let module_name = module_name_of_node n.semantics.sem_nname in
  let is_initial_only = function LG _ -> false | _ -> true in
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
          td_def = TDalgebraic (List.map (fun s -> (loc, ident s, [])) n.semantics.sem_states);
        };
      ]
  in
  let summary_by_name =
    runtime.callee_summaries
    |> List.map (fun (summary : Why_runtime_view.callee_summary_view) -> (summary.callee_node_name, summary))
  in
  let used_callee_summaries =
    n.semantics.sem_instances
    |> List.filter_map (fun (_, node_name) -> List.assoc_opt node_name summary_by_name)
    |> List.sort_uniq
         (fun (a : Why_runtime_view.callee_summary_view) (b : Why_runtime_view.callee_summary_view) ->
           String.compare a.callee_node_name b.callee_node_name)
  in
  let instance_type_decls =
    let is_ghost_local name =
      (String.length name >= 7 && String.sub name 0 7 = "__atom_")
      || (String.length name >= 5 && String.sub name 0 5 = "atom_")
      || (String.length name >= 6 && String.sub name 0 6 = "__aut_")
      || (String.length name >= 6 && String.sub name 0 6 = "__pre_")
    in
    used_callee_summaries
    |> List.concat_map (fun (summary : Why_runtime_view.callee_summary_view) ->
           let state_decl =
             Ptree.Dtype
               [
                 {
                   td_loc = loc;
                   td_ident = ident (instance_state_type_name summary.callee_node_name);
                   td_params = [];
                   td_vis = Public;
                   td_mut = false;
                   td_inv = [];
                   td_wit = None;
                   td_def =
                     TDalgebraic
                       (List.map
                          (fun state_name ->
                            (loc, ident (instance_state_ctor_name summary.callee_node_name state_name), []))
                          summary.callee_states);
                 };
               ]
           in
           let state_field =
             {
               f_loc = loc;
               f_ident = ident (prefix_for_node summary.callee_node_name ^ "st");
               f_pty = Ptree.PTtyapp (qid1 (instance_state_type_name summary.callee_node_name), []);
               f_mutable = true;
               f_ghost = false;
             }
           in
           let local_fields =
             List.map
               (fun (port : Why_runtime_view.port_view) ->
                 {
                   f_loc = loc;
                   f_ident = ident (prefix_for_node summary.callee_node_name ^ port.port_name);
                   f_pty = default_pty port.port_type;
                   f_mutable = true;
                   f_ghost = is_ghost_local port.port_name;
                 })
               summary.callee_locals
           in
           let output_fields =
             List.map
               (fun (port : Why_runtime_view.port_view) ->
                 {
                   f_loc = loc;
                   f_ident = ident (prefix_for_node summary.callee_node_name ^ port.port_name);
                   f_pty = default_pty port.port_type;
                   f_mutable = true;
                   f_ghost = false;
                 })
               summary.callee_outputs
           in
           let vars_decl =
             Ptree.Dtype
               [
                 {
                   td_loc = loc;
                   td_ident = ident (instance_vars_type_name summary.callee_node_name);
                   td_params = [];
                   td_vis = Public;
                   td_mut = true;
                   td_inv = [];
                   td_wit = None;
                   td_def = TDrecord (state_field :: (local_fields @ output_fields));
                 };
               ]
           in
           [ state_decl; vars_decl ])
  in
  let pre_k_infos = List.map snd pre_k_map in
  let inv_links = runtime.user_invariants |> List.map (fun inv -> (inv.inv_expr, inv.inv_id)) in
  let field_prefix = if prefix_fields then prefix_for_node n.semantics.sem_nname else "" in
  let input_names = Ast_queries.input_names_of_node n in
  let base_vars =
    ("st" :: List.map (fun v -> v.vname) (n.semantics.sem_locals @ n.semantics.sem_outputs))
    @ List.map fst n.semantics.sem_instances
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
      inst_map = n.semantics.sem_instances;
      inputs = input_names;
    }
  in
  let instance_fields =
    List.map
      (fun (inst_name, node_name) ->
        {
          f_loc = loc;
          f_ident = ident (rec_var_name env inst_name);
          f_pty = Ptree.PTtyapp (qid1 (instance_vars_type_name node_name), []);
          f_mutable = true;
          f_ghost = false;
        })
      n.semantics.sem_instances
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
      n.semantics.sem_locals
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
      n.semantics.sem_outputs
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
  let output_exprs = List.map (fun v -> field env v.vname) n.semantics.sem_outputs in
  let vars_param = (loc, Some (ident "vars"), false, Some (Ptree.PTtyapp (qid1 "vars", []))) in
  let inputs =
    match n.semantics.sem_inputs with
    | [] -> [ vars_param ]
    | _ ->
        vars_param
        :: List.map
             (fun v -> (loc, Some (ident v.vname), false, Some (default_pty v.vty)))
             n.semantics.sem_inputs
  in
  let ret_expr =
    match output_exprs with
    | [] -> mk_expr (Etuple [])
    | [ e ] -> e
    | es -> mk_expr (Etuple es)
  in
  let node = n in
  {
    runtime_view = runtime;
    module_name;
    imports;
    instance_type_decls;
    type_state;
    type_vars;
    env;
    inputs;
    ret_expr;
    pre_k_map;
    pre_k_infos;
    hexpr_needs_old;
    input_names;
  }

let prepare_ir_node ~(prefix_fields : bool) (node : Ir.node_ir) : Why_types.env_info =
  let runtime = Why_runtime_view.of_ir_node node in
  prepare_runtime_view ~prefix_fields ~pre_k_map:node.context.pre_k_map runtime
