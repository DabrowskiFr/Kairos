(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

[@@@ocaml.warning "-8-26-27-32-33"]

open Ast
open Ast_builders
open Support

let s desc = mk_stmt desc
let mk_e desc = mk_iexpr desc

let add_local_if_missing (locals : vdecl list) ~(inputs : vdecl list) ~(outputs : vdecl list)
    (name : ident) (vty : ty) : vdecl list =
  let exists =
    List.exists (fun v -> v.vname = name) inputs
    || List.exists (fun v -> v.vname = name) outputs
    || List.exists (fun v -> v.vname = name) locals
  in
  if exists then locals else locals @ [ { vname = name; vty } ]

let pre_k_source_expr (e : iexpr) : iexpr = e

(* Compile source-level history operators [pre_k]/[prev] into finite auxiliary
   state carried by the backend. This is an implementation device: the source
   specification remains interpreted over the execution trace, not over these
   auxiliary variables directly. *)
let transform_node_ghost_with_info (n : Ast.node) : Ast.node * Stage_info.obc_info =
  let n = n in
  let orig_locals = n.locals in
  let init_for_var =
    let table = List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs) in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> mk_bool false
      | Some TInt -> mk_int 0
      | Some TReal -> mk_int 0
      | Some (TCustom _) | None -> mk_int 0
  in
  let is_initial_only = function LG _ -> false | _ -> true in
  let pre_k_map = Collect.build_pre_k_infos n in
  let pre_k_infos = List.map snd pre_k_map in
  let spec = Ast.specification_of_node n in
  let has_initial_only_contracts =
    List.exists is_initial_only (spec.spec_assumes @ spec.spec_guarantees)
  in
  let needs_step_count = false in
  let needs_first_step = false in

  let locals =
    let locals = ref n.locals in
    List.iter
      (fun info ->
        List.iter
          (fun name ->
            locals := add_local_if_missing !locals ~inputs:n.inputs ~outputs:n.outputs name info.vty)
          info.names)
      pre_k_infos;
    !locals
  in
  let ghost_locals_added =
    let existing = List.map (fun v -> v.vname) orig_locals in
    locals |> List.filter (fun v -> not (List.mem v.vname existing)) |> List.map (fun v -> v.vname)
  in

  let pre_old_updates = [] in
  let pre_old_local_updates = [] in
  let pre_updates = [] in
  let pre_k_updates =
    List.concat_map
      (fun info ->
        let names = info.names in
        let shifts =
          let rec loop i acc =
            if i <= 1 then acc
            else
              let tgt = List.nth names (i - 1) in
              let src = List.nth names (i - 2) in
              loop (i - 1) (acc @ [ s (SAssign (tgt, mk_var src)) ])
          in
          loop (List.length names) []
        in
        let first =
          match names with
          | [] -> []
          | name :: _ -> [ s (SAssign (name, pre_k_source_expr info.expr)) ]
        in
        shifts @ first)
      pre_k_infos
  in
  let pre_k_links : fo_o list = [] in
  let ghost_base = [] in
  let reset_flags = [] in
  let trans =
    List.map
      (fun (t : transition) ->
        let _ghost = ghost_base in
        let _reset = reset_flags in
        {
          t with
          attrs =
            {
              t.attrs with
              (* History variables must be updated after user code so post-state
                 obligations interpret [prev]/[pre_k] over the new step. *)
              instrumentation = t.attrs.instrumentation @ pre_k_updates;
            };
          ensures = t.ensures @ pre_k_links;
        })
      n.trans
  in
  let info =
    {
      Stage_info.ghost_locals_added;
      Stage_info.pre_k_infos = List.map (fun info -> info.names) pre_k_infos;
      Stage_info.warnings = [];
    }
  in
  ({ n with locals; trans }, info)

let transform_node_ghost (n : Ast.node) : Ast.node =
  let node, _info = transform_node_ghost_with_info n in
  node
