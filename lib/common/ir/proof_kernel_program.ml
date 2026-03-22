open Ast
open Support
open Fo_specs

module Abs = Normalized_program
module PT = Product_types
open Proof_kernel_types

let fo_of_iexpr (e : iexpr) : ltl = iexpr_to_fo_with_atoms [] e

let build_reactive_program ~(node_name : Ast.ident) ~(node : Abs.node) : reactive_program_ir =
  let transitions =
    List.mapi
      (fun idx (t : Abs.transition) ->
        {
          transition_id = Printf.sprintf "tr_%d" idx;
          src_state = t.src;
          dst_state = t.dst;
          guard =
            (match t.guard with
            | None -> LTrue
            | Some g -> fo_of_iexpr g |> Fo_simplifier.simplify_fo);
          guard_iexpr = t.guard;
          requires = t.requires;
          ensures = t.ensures;
          ghost_stmts = t.attrs.ghost;
          body_stmts = t.body;
          instrumentation_stmts = t.attrs.instrumentation;
        })
      node.trans
  in
  {
    node_name;
    init_state = node.semantics.sem_init_state;
    states = node.semantics.sem_states;
    transitions;
  }

let build_automaton ~(role : automaton_role) ~(labels : string list) ~(bad_idx : int)
    ~(grouped_edges : PT.automaton_edge list) ~(atom_map_exprs : (Ast.ident * Ast.iexpr) list)
    ~automaton_guard_fo : safety_automaton_ir =
  let edges =
    List.map
      (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
        {
          src_index = src;
          dst_index = dst;
          guard = automaton_guard_fo atom_map_exprs guard_raw;
        })
      grouped_edges
  in
  {
    role;
    initial_state_index = 0;
    bad_state_index = if bad_idx < 0 then None else Some bad_idx;
    state_labels = List.mapi (fun i lbl -> (i, lbl)) labels;
    edges;
  }

let program_transition_id_of_step ~(reactive_program : reactive_program_ir) (step : PT.product_step) :
    string =
  let matches (tr : reactive_transition_ir) =
    String.equal tr.src_state step.prog_transition.src
    && String.equal tr.dst_state step.prog_transition.dst
    && Fo_simplifier.simplify_fo tr.guard = Fo_simplifier.simplify_fo step.prog_guard
  in
  match List.find_opt matches reactive_program.transitions with
  | Some tr -> tr.transition_id
  | None ->
      failwith
        (Printf.sprintf
           "Unable to associate product step %s->%s with a reactive transition in node %s"
           step.prog_transition.src step.prog_transition.dst reactive_program.node_name)

let build_product_step ~(reactive_program : reactive_program_ir) (step : PT.product_step) : product_step_ir =
  {
    src =
      {
        prog_state = step.src.prog_state;
        assume_state_index = step.src.assume_state;
        guarantee_state_index = step.src.guarantee_state;
      };
    dst =
      {
        prog_state = step.dst.prog_state;
        assume_state_index = step.dst.assume_state;
        guarantee_state_index = step.dst.guarantee_state;
      };
    program_transition_id = program_transition_id_of_step ~reactive_program step;
    program_transition = (step.prog_transition.src, step.prog_transition.dst);
    program_guard = step.prog_guard;
    assume_edge =
      (let src, _guard, dst = step.assume_edge in
       { src_index = src; dst_index = dst; guard = step.assume_guard });
    guarantee_edge =
      (let src, _guard, dst = step.guarantee_edge in
       { src_index = src; dst_index = dst; guard = step.guarantee_guard });
    step_kind =
      (match step.step_class with
      | PT.Safe -> StepSafe
      | PT.Bad_assumption -> StepBadAssumption
      | PT.Bad_guarantee -> StepBadGuarantee);
    step_origin = StepFromExplicitExploration;
  }

let invariant_formula_for_state ~(node : Abs.node) (state_name : Ast.ident) : Ast.ltl option =
  let formulas =
    node.specification.spec_invariants_state_rel
    |> List.filter_map (fun (inv : Ast.invariant_state_rel) ->
           if (inv.is_eq && inv.state = state_name) || ((not inv.is_eq) && inv.state <> state_name)
           then Some inv.formula
           else None)
  in
  match formulas with
  | [] -> None
  | hd :: tl -> Some (List.fold_left (fun acc fo -> Ast.LAnd (acc, fo)) hd tl)

type current_const =
  | CInt of int
  | CBool of bool

type current_constraint_env = {
  parent : (Ast.ident, Ast.ident) Hashtbl.t;
  const_of_root : (Ast.ident, current_const) Hashtbl.t;
  forbids_of_root : (Ast.ident, current_const list) Hashtbl.t;
}

let empty_current_constraint_env () =
  {
    parent = Hashtbl.create 16;
    const_of_root = Hashtbl.create 16;
    forbids_of_root = Hashtbl.create 16;
  }

let rec find_root env v =
  match Hashtbl.find_opt env.parent v with
  | None ->
      Hashtbl.replace env.parent v v;
      v
  | Some p when p = v -> v
  | Some p ->
      let root = find_root env p in
      Hashtbl.replace env.parent v root;
      root

let const_equal a b =
  match (a, b) with
  | CInt x, CInt y -> x = y
  | CBool x, CBool y -> Bool.equal x y
  | _ -> false

let add_forbid env root c =
  let prev = Hashtbl.find_opt env.forbids_of_root root |> Option.value ~default:[] in
  if List.exists (const_equal c) prev then ()
  else Hashtbl.replace env.forbids_of_root root (c :: prev)

let root_forbids env root c =
  Hashtbl.find_opt env.forbids_of_root root
  |> Option.value ~default:[]
  |> List.exists (const_equal c)

let assign_const env root c =
  match Hashtbl.find_opt env.const_of_root root with
  | Some existing when not (const_equal existing c) -> false
  | Some _ -> not (root_forbids env root c)
  | None ->
      if root_forbids env root c then false
      else (
        Hashtbl.replace env.const_of_root root c;
        true)

let merge_roots env r1 r2 =
  if r1 = r2 then true
  else
    let c1 = Hashtbl.find_opt env.const_of_root r1 in
    let c2 = Hashtbl.find_opt env.const_of_root r2 in
    match (c1, c2) with
    | Some a, Some b when not (const_equal a b) -> false
    | _ ->
        Hashtbl.replace env.parent r2 r1;
        begin
          match c1 with
          | Some _ -> ()
          | None -> Option.iter (fun c -> Hashtbl.replace env.const_of_root r1 c) c2
        end;
        let forbids =
          (Hashtbl.find_opt env.forbids_of_root r1 |> Option.value ~default:[])
          @ (Hashtbl.find_opt env.forbids_of_root r2 |> Option.value ~default:[])
        in
        Hashtbl.replace env.forbids_of_root r1 forbids;
        begin
          match Hashtbl.find_opt env.const_of_root r1 with
          | Some c when root_forbids env r1 c -> false
          | _ -> true
        end

let clone_constraint_env env =
  let copy_tbl tbl =
    let out = Hashtbl.create (Hashtbl.length tbl * 2 + 1) in
    Hashtbl.iter (fun k v -> Hashtbl.replace out k v) tbl;
    out
  in
  {
    parent = copy_tbl env.parent;
    const_of_root = copy_tbl env.const_of_root;
    forbids_of_root = copy_tbl env.forbids_of_root;
  }

let current_const_of_iexpr (e : Ast.iexpr) : current_const option =
  match e.iexpr with
  | Ast.ILitInt n -> Some (CInt n)
  | Ast.ILitBool b -> Some (CBool b)
  | _ -> None

let current_var_of_hexpr = function
  | Ast.HNow { iexpr = Ast.IVar v; _ } -> Some v
  | _ -> None

let current_const_of_hexpr = function
  | Ast.HNow e -> current_const_of_iexpr e
  | _ -> None

let add_current_atom env ~(negated : bool) (fo : Ast.fo) : bool option =
  match fo with
  | Ast.FRel (h1, Ast.REq, h2) -> begin
      match
        ( current_var_of_hexpr h1,
          current_var_of_hexpr h2,
          current_const_of_hexpr h1,
          current_const_of_hexpr h2 )
      with
      | Some v, _, _, Some c ->
          let root = find_root env v in
          if negated then (
            add_forbid env root c;
            match Hashtbl.find_opt env.const_of_root root with
            | Some assigned when const_equal assigned c -> Some false
            | _ -> Some true)
          else Some (assign_const env root c)
      | _, Some v, Some c, _ ->
          let root = find_root env v in
          if negated then (
            add_forbid env root c;
            match Hashtbl.find_opt env.const_of_root root with
            | Some assigned when const_equal assigned c -> Some false
            | _ -> Some true)
          else Some (assign_const env root c)
      | Some v1, Some v2, _, _ when not negated ->
          Some (merge_roots env (find_root env v1) (find_root env v2))
      | _ -> None
    end
  | _ -> None

let rec current_formula_maybe_satisfiable env (fo : Ast.ltl) : bool =
  match fo with
  | Ast.LTrue -> true
  | Ast.LFalse -> false
  | Ast.LAtom atom -> begin
      match add_current_atom env ~negated:false atom with
      | Some b -> b
      | None -> true
    end
  | Ast.LNot (Ast.LAtom atom) -> begin
      match add_current_atom env ~negated:true atom with
      | Some b -> b
      | None -> true
    end
  | Ast.LNot inner -> not (current_formula_maybe_satisfiable env inner)
  | Ast.LAnd (a, b) ->
      current_formula_maybe_satisfiable env a && current_formula_maybe_satisfiable env b
  | Ast.LOr (a, b) ->
      let env_left = clone_constraint_env env in
      current_formula_maybe_satisfiable env_left a || current_formula_maybe_satisfiable env b
  | Ast.LImp _ | Ast.LX _ | Ast.LG _ | Ast.LW _ -> true

let is_feasible_product_step ~(node : Abs.node) ~(analysis : Product_build.analysis)
    (step : product_step_ir) : bool =
  let src_live =
    step.src.assume_state_index <> analysis.assume_bad_idx
    && step.src.guarantee_state_index <> analysis.guarantee_bad_idx
  in
  src_live
  &&
  match invariant_formula_for_state ~node step.dst.prog_state with
  | None -> true
  | Some dst_inv ->
      current_formula_maybe_satisfiable
        (empty_current_constraint_env ())
        (Ast.LAnd (step.guarantee_edge.guard, dst_inv))

let synthesize_fallback_product_steps ~(node : Abs.node) ~(analysis : Product_build.analysis)
    ~(reactive_program : reactive_program_ir) ~(live_states : PT.product_state list)
    ~automaton_guard_fo ~product_state_of_pt:_ ~product_step_kind_of_pt:_ ~is_live_state:_ :
    product_step_ir list =
  let live_states = List.sort_uniq PT.compare_state live_states in
  let assume_edges =
    List.map
      (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
        (src, dst, automaton_guard_fo analysis.assume_atom_map_exprs guard_raw))
      analysis.assume_grouped_edges
  in
  let guarantee_edges =
    List.map
      (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
        (src, dst, automaton_guard_fo analysis.guarantee_atom_map_exprs guard_raw))
      analysis.guarantee_grouped_edges
  in
  let matching_edges edges src dst =
    edges
    |> List.filter_map (fun (s, d, g) -> if s = src && d = dst then Some g else None)
    |> List.sort_uniq Stdlib.compare
  in
  let transition_id_for ~(src : Ast.ident) ~(dst : Ast.ident) ~(guard : Ast.ltl) =
    match
      List.find_opt
        (fun (tr : reactive_transition_ir) ->
          String.equal tr.src_state src
          && String.equal tr.dst_state dst
          && Fo_simplifier.simplify_fo tr.guard = Fo_simplifier.simplify_fo guard)
        reactive_program.transitions
    with
    | Some tr -> tr.transition_id
    | None ->
        failwith
          (Printf.sprintf
             "Unable to associate fallback product step %s->%s with a reactive transition in node %s"
             src dst reactive_program.node_name)
  in
  node.trans
  |> List.concat_map (fun (t : Abs.transition) ->
         let program_guard =
           match t.guard with
           | None -> LTrue
           | Some g -> Fo_simplifier.simplify_fo (fo_of_iexpr g)
         in
         live_states
         |> List.filter (fun (st : PT.product_state) -> st.prog_state = t.src)
         |> List.concat_map (fun (src : PT.product_state) ->
                live_states
                |> List.filter (fun (st : PT.product_state) -> st.prog_state = t.dst)
                |> List.filter_map (fun (dst : PT.product_state) ->
                       let assume_guards = matching_edges assume_edges src.assume_state dst.assume_state in
                       let guarantee_guards =
                         matching_edges guarantee_edges src.guarantee_state dst.guarantee_state
                       in
                       let assume_guard =
                         match assume_guards with
                         | [] -> None
                         | [ g ] -> Some g
                         | g :: gs -> Some (List.fold_left (fun acc x -> LOr (acc, x)) g gs)
                       in
                       let guarantee_guard =
                         match guarantee_guards with
                         | [] -> None
                         | [ g ] -> Some g
                         | g :: gs -> Some (List.fold_left (fun acc x -> LOr (acc, x)) g gs)
                       in
                       match (assume_guard, guarantee_guard) with
                       | Some ag, Some gg ->
                           let combined =
                             Fo_simplifier.simplify_fo (LAnd (program_guard, LAnd (ag, gg)))
                           in
                           if combined = LFalse then None
                           else
                             Some
                               {
                                 src =
                                   {
                                     prog_state = src.prog_state;
                                     assume_state_index = src.assume_state;
                                     guarantee_state_index = src.guarantee_state;
                                   };
                                 dst =
                                   {
                                     prog_state = dst.prog_state;
                                     assume_state_index = dst.assume_state;
                                     guarantee_state_index = dst.guarantee_state;
                                   };
                                 program_transition_id =
                                   transition_id_for ~src:t.src ~dst:t.dst ~guard:program_guard;
                                 program_transition = (t.src, t.dst);
                                 program_guard;
                                 assume_edge =
                                   { src_index = src.assume_state; dst_index = dst.assume_state; guard = ag };
                                 guarantee_edge =
                                   { src_index = src.guarantee_state; dst_index = dst.guarantee_state; guard = gg };
                                 step_kind = StepSafe;
                                 step_origin = StepFromFallbackSynthesis;
                               }
                       | _ -> None)))
