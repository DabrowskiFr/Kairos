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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Core_syntax

module B = Core_syntax_builders
module StringMap = Map.Make (String)
module StringSet = Set.Make (String)

let fail fmt =
  Printf.ksprintf Kx_frontend_error.elaboration fmt

let generated_prefix owner instance =
  "__kairos_instance_" ^ owner ^ "_" ^ instance ^ "_"

let rec calls_in_stmt (stmt : stmt) =
  match stmt.stmt with
  | SCall (callee, _, _) -> [ callee ]
  | SIf (_, then_branch, else_branch) ->
      List.concat_map calls_in_stmt (then_branch @ else_branch)
  | SWhile (_, _, _, body) -> List.concat_map calls_in_stmt body
  | SMatch (_, branches, default_branch) ->
      List.concat_map calls_in_stmt
        (List.concat_map snd branches @ default_branch)
  | SAssign _ | SAssert _ | SSkip -> []

let calls_in_node (node : Verification_model.node_model) =
  List.concat_map
    (fun (step : Verification_model.program_step) ->
      List.concat_map calls_in_stmt step.body_stmts)
    node.steps

let nested_call (stmt : stmt) =
  match stmt.stmt with
  | SCall _ | SAssign _ | SAssert _ | SSkip -> None
  | SIf (_, then_branch, else_branch) ->
      List.find_map
        (fun inner ->
          match calls_in_stmt inner with
          | [] -> None
          | callee :: _ -> Some callee)
        (then_branch @ else_branch)
  | SWhile (_, _, _, body) ->
      List.find_map
        (fun inner ->
          match calls_in_stmt inner with
          | [] -> None
          | callee :: _ -> Some callee)
        body
  | SMatch (_, branches, default_branch) ->
      List.find_map
        (fun inner ->
          match calls_in_stmt inner with
          | [] -> None
          | callee :: _ -> Some callee)
        (List.concat_map snd branches @ default_branch)

let top_level_calls (step : Verification_model.program_step) =
  List.filter_map
    (fun (stmt : stmt) ->
      match stmt.stmt with SCall (callee, _, _) -> Some callee | _ -> None)
    step.body_stmts

let duplicate_name names =
  let rec loop seen = function
    | [] -> None
    | name :: rest ->
        if StringSet.mem name seen then Some name
        else loop (StringSet.add name seen) rest
  in
  loop StringSet.empty names

let rec subst_expr names (expr : expr) =
  let desc =
    match expr.expr with
    | ELitInt _ | ELitBool _ | ELitEnum _ as literal -> literal
    | EVar name ->
        EVar (StringMap.find_opt name names |> Option.value ~default:name)
    | EFunCall (name, args) ->
        EFunCall (name, List.map (subst_expr names) args)
    | EBin (op, left, right) ->
        EBin (op, subst_expr names left, subst_expr names right)
    | ECmp (op, left, right) ->
        ECmp (op, subst_expr names left, subst_expr names right)
    | EUn (op, inner) -> EUn (op, subst_expr names inner)
  in
  { expr with expr = desc }

let rec subst_hexpr :
    type phase.
    ident StringMap.t ->
    phase hexpr ->
    phase hexpr =
 fun names formula ->
  match formula.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ -> formula
  | HVar name ->
      B.with_hexpr_desc formula
        (HVar
           (StringMap.find_opt name names |> Option.value ~default:name))
  | HPreK (name, depth) ->
      B.with_hexpr_desc formula
        (HPreK
           ( StringMap.find_opt name names |> Option.value ~default:name,
             depth ))
  | HPred (name, args) ->
      B.with_hexpr_desc formula
        (HPred (name, List.map (subst_hexpr names) args))
  | HFunCall (name, args) ->
      B.with_hexpr_desc formula
        (HFunCall (name, List.map (subst_hexpr names) args))
  | HBin (op, left, right) ->
      B.with_hexpr_desc formula
        (HBin
           (op, subst_hexpr names left, subst_hexpr names right))
  | HCmp (op, left, right) ->
      B.with_hexpr_desc formula
        (HCmp
           (op, subst_hexpr names left, subst_hexpr names right))
  | HUn (op, inner) ->
      B.with_hexpr_desc formula
        (HUn (op, subst_hexpr names inner))

let rec subst_ltl names = function
  | LTrue -> LTrue
  | LFalse -> LFalse
  | LAtom (left, op, right) ->
      LAtom (subst_hexpr names left, op, subst_hexpr names right)
  | LNot formula -> LNot (subst_ltl names formula)
  | LAnd (left, right) ->
      LAnd (subst_ltl names left, subst_ltl names right)
  | LOr (left, right) ->
      LOr (subst_ltl names left, subst_ltl names right)
  | LImp (left, right) ->
      LImp (subst_ltl names left, subst_ltl names right)
  | LX formula -> LX (subst_ltl names formula)
  | LG formula -> LG (subst_ltl names formula)
  | LW (left, right) ->
      LW (subst_ltl names left, subst_ltl names right)

let rec subst_stmt names (stmt : stmt) =
  let rename name =
    StringMap.find_opt name names |> Option.value ~default:name
  in
  let desc =
    match stmt.stmt with
    | SAssign (target, rhs) ->
        SAssign (rename target, subst_expr names rhs)
    | SAssert formula -> SAssert (subst_hexpr names formula)
    | SIf (condition, then_branch, else_branch) ->
        SIf
          ( subst_expr names condition,
            List.map (subst_stmt names) then_branch,
            List.map (subst_stmt names) else_branch )
    | SWhile (condition, invariants, variant, body) ->
        SWhile
          ( subst_expr names condition,
            List.map (subst_hexpr names) invariants,
            Option.map (subst_expr names) variant,
            List.map (subst_stmt names) body )
    | SMatch (scrutinee, branches, default_branch) ->
        SMatch
          ( subst_expr names scrutinee,
            List.map
              (fun (ctor, body) ->
                (ctor, List.map (subst_stmt names) body))
              branches,
            List.map (subst_stmt names) default_branch )
    | SSkip -> SSkip
    | SCall _ ->
        fail
          "internal error: hierarchy inlining encountered a nested unexpanded call"
  in
  { stmt with stmt = desc }

let mk_stmt ?loc desc : stmt = { stmt = desc; loc }

let expr_eq_int name value =
  B.mk_expr (ECmp (REq, B.mk_var name, B.mk_int value))

let h_eq_int name value =
  B.mk_hexpr (HCmp (REq, B.mk_hvar name, B.mk_hint value))

let h_ge_int name value =
  B.mk_hexpr (HCmp (RGe, B.mk_hvar name, B.mk_hint value))

let h_lt_int name value =
  B.mk_hexpr (HCmp (RLt, B.mk_hvar name, B.mk_hint value))

type instance_info = {
  instance_name : ident;
  callee : Verification_model.node_model;
  state_var : ident;
  transition_var : ident;
  names : ident StringMap.t;
  input_bindings : ident list;
  output_storage : vdecl list;
  local_storage : vdecl list;
  ghost_storage : vdecl list;
  public_ghost_storage : ident list;
  state_codes : (ident * int) list;
  transition_codes : (Verification_model.program_step * int) list;
}

let rename_decl prefix category (decl : vdecl) =
  { decl with vname = prefix ^ category ^ decl.vname }

let add_decl_names names originals generated =
  List.fold_left2
    (fun acc (original : vdecl) (renamed : vdecl) ->
      StringMap.add original.vname renamed.vname acc)
    names originals generated

let make_instance_info owner instance_name input_bindings
    (callee : Verification_model.node_model) =
  let prefix = generated_prefix owner instance_name in
  if List.length input_bindings <> List.length callee.inputs then
    fail
      "node '%s': call to instance '%s' expects %d input(s) but got %d"
      owner instance_name (List.length callee.inputs)
      (List.length input_bindings);
  let output_storage =
    List.map (rename_decl prefix "output_") callee.outputs
  in
  let local_storage = List.map (rename_decl prefix "local_") callee.locals in
  let ghost_storage = List.map (rename_decl prefix "ghost_") callee.ghosts in
  let names =
    StringMap.empty
    |> fun map ->
    List.fold_left2
      (fun acc (input : vdecl) binding ->
        StringMap.add input.vname binding acc)
      map callee.inputs input_bindings
    |> fun map -> add_decl_names map callee.outputs output_storage
    |> fun map -> add_decl_names map callee.locals local_storage
    |> fun map -> add_decl_names map callee.ghosts ghost_storage
  in
  let rename_public name =
    StringMap.find_opt name names
    |> Option.value ~default:(prefix ^ "ghost_" ^ name)
  in
  {
    instance_name;
    callee;
    state_var = prefix ^ "control";
    transition_var = prefix ^ "transition";
    names;
    input_bindings;
    output_storage;
    local_storage;
    ghost_storage;
    public_ghost_storage = List.map rename_public callee.public_ghosts;
    state_codes = List.mapi (fun code state -> (state, code)) callee.states;
    transition_codes =
      List.mapi (fun code step -> (step, code)) callee.steps;
  }

let code_of_state info state =
  match List.assoc_opt state info.state_codes with
  | Some code -> code
  | None ->
      fail "node '%s': instance '%s' has unknown state '%s'"
        info.callee.node_name info.instance_name state

let transition_checks info =
  List.concat_map
    (fun ((step : Verification_model.program_step), code) ->
      List.map
        (fun check ->
          B.mk_himp
            (h_eq_int info.transition_var code)
            (subst_hexpr info.names check))
        step.elaboration_checks)
    info.transition_codes

let rec guarded_step_chain info steps =
  match steps with
  | [] ->
      [
        mk_stmt
          (SAssert
             (B.mk_hbool false));
      ]
  | ((step : Verification_model.program_step), transition_code) :: rest ->
      let condition =
        match step.guard_expr with
        | None -> B.mk_bool true
        | Some guard -> subst_expr info.names guard
      in
      let body =
        List.map (subst_stmt info.names) step.body_stmts
        @ [
            mk_stmt
              (SAssign
                 (info.state_var, B.mk_int (code_of_state info step.dst_state)));
            mk_stmt
              (SAssign (info.transition_var, B.mk_int transition_code));
          ]
      in
      [ mk_stmt (SIf (condition, body, guarded_step_chain info rest)) ]

let dispatch_for_state info (state, state_code) =
  let steps =
    List.filter
      (fun ((step : Verification_model.program_step), _) ->
        String.equal step.src_state state)
      info.transition_codes
  in
  (expr_eq_int info.state_var state_code, guarded_step_chain info steps)

let rec state_dispatch = function
  | [] -> [ mk_stmt (SAssert (B.mk_hbool false)) ]
  | (condition, body) :: rest ->
      [ mk_stmt (SIf (condition, body, state_dispatch rest)) ]

let expand_call ~initial owner info args destinations =
  if List.length args <> List.length info.callee.inputs then
    fail
      "node '%s': call to instance '%s' expects %d input(s) but got %d"
      owner info.instance_name (List.length info.callee.inputs)
      (List.length args);
  if List.length destinations <> List.length info.callee.outputs then
    fail
      "node '%s': call to instance '%s' returns %d output(s) but got %d destination(s)"
      owner info.instance_name (List.length info.callee.outputs)
      (List.length destinations);
  let argument_names =
    List.map
      (fun argument ->
        match argument.expr with
        | EVar name -> name
        | _ ->
            fail
              "node '%s': instance '%s' arguments must be variable references so contracts have an unambiguous trace-level binding"
              owner info.instance_name)
      args
  in
  if argument_names <> info.input_bindings then
    fail
      "node '%s': instance '%s' input bindings changed across transitions"
      owner info.instance_name;
  let output_assignments =
    List.map2
      (fun destination (storage : vdecl) ->
        mk_stmt (SAssign (destination, B.mk_var storage.vname)))
      destinations info.output_storage
  in
  let dispatch =
    if initial then
      (* [flatten_one] writes the instance's initial state immediately before
         calls issued by the owner's dedicated init transition. Expanding the
         complete state dispatcher here is semantically redundant and can
         duplicate most of a composite program in generated C. Keep only the
         transitions that can actually leave the callee's initial state. *)
      let init_steps =
        List.filter
          (fun ((step : Verification_model.program_step), _) ->
            String.equal step.src_state info.callee.init_state)
          info.transition_codes
      in
      guarded_step_chain info init_steps
    else
      state_dispatch (List.map (dispatch_for_state info) info.state_codes)
  in
  dispatch @ output_assignments

let validate_schedule owner expected_names
    (steps : Verification_model.program_step list) =
  let expected_set =
    List.fold_left
      (fun set name -> StringSet.add name set)
      StringSet.empty expected_names
  in
  let baseline = ref None in
  List.iter
    (fun (step : Verification_model.program_step) ->
      List.iter
        (fun stmt ->
          match nested_call stmt with
          | None -> ()
          | Some callee ->
              fail
                "node '%s': call to '%s' is nested; weak hierarchy requires calls at transition top level"
                owner callee)
        step.body_stmts;
      let schedule = top_level_calls step in
      (match duplicate_name schedule with
      | Some name ->
          fail
            "node '%s': instance '%s' is called more than once in transition %s -> %s"
            owner name step.src_state step.dst_state
      | None -> ());
      let schedule_set =
        List.fold_left
          (fun set name -> StringSet.add name set)
          StringSet.empty schedule
      in
      if not (StringSet.equal expected_set schedule_set) then
        fail
          "node '%s': every transition must call each instance exactly once; transition %s -> %s calls [%s], expected [%s]"
          owner step.src_state step.dst_state
          (String.concat ", " schedule)
          (String.concat ", " expected_names);
      match !baseline with
      | None -> baseline := Some schedule
      | Some first when first = schedule -> ()
      | Some first ->
          fail
            "node '%s': all transitions must call instances in the same order; transition %s -> %s uses [%s], expected [%s]"
            owner step.src_state step.dst_state
            (String.concat ", " schedule)
            (String.concat ", " first))
    steps

let binding_for_instance owner instance_name
    (steps : Verification_model.program_step list) =
  let baseline = ref None in
  List.iter
    (fun (step : Verification_model.program_step) ->
      let call =
        List.find_map
          (fun (stmt : stmt) ->
            match stmt.stmt with
            | SCall (callee, args, destinations)
              when String.equal callee instance_name ->
                Some (args, destinations)
            | _ -> None)
          step.body_stmts
      in
      let args, destinations =
        match call with
        | Some call -> call
        | None ->
            fail
              "node '%s': internal error: transition %s -> %s has no call to instance '%s'"
              owner step.src_state step.dst_state instance_name
      in
      let input_names =
        List.map
          (fun argument ->
            match argument.expr with
            | EVar name -> name
            | _ ->
                fail
                  "node '%s': instance '%s' arguments must be variable references so contracts have an unambiguous trace-level binding"
                  owner instance_name)
          args
      in
      let shape = (input_names, destinations) in
      match !baseline with
      | None -> baseline := Some shape
      | Some first when first = shape -> ()
      | Some _ ->
          fail
            "node '%s': instance '%s' must use the same input and output bindings on every transition"
            owner instance_name)
    steps;
  match !baseline with
  | Some shape -> shape
  | None -> fail "node '%s': instance '%s' has no call site" owner instance_name

let resolve_instance_decls ~nodes_by_name ~declared
    (node : Verification_model.node_model) =
  let declared_names = List.map fst declared in
  (match duplicate_name declared_names with
  | Some name ->
      fail "node '%s': duplicate instance name '%s'" node.node_name name
  | None -> ());
  List.iter
    (fun (instance_name, callee_name) ->
      if not (StringMap.mem callee_name nodes_by_name) then
        fail "node '%s': instance '%s' references unknown node '%s'"
          node.node_name instance_name callee_name)
    declared;
  let declared_map =
    List.fold_left
      (fun map (instance_name, callee_name) ->
        StringMap.add instance_name callee_name map)
      StringMap.empty declared
  in
  let calls = calls_in_node node in
  let implicit =
    List.fold_left
      (fun acc callee ->
        if StringMap.mem callee declared_map || List.mem_assoc callee acc then
          acc
        else if StringMap.mem callee nodes_by_name then
          acc @ [ (callee, callee) ]
        else
          fail
            "node '%s': call target '%s' is neither a declared instance nor a node"
            node.node_name callee)
      [] calls
  in
  let all = declared @ implicit in
  List.iter
    (fun (instance_name, _) ->
      if not (List.mem instance_name calls) then
        fail "node '%s': instance '%s' is declared but never called"
          node.node_name instance_name)
    all;
  all

let lift_instance_guarantees info =
  let assumptions = List.map (subst_ltl info.names) info.callee.assumes in
  let guarantees =
    List.map (subst_ltl info.names) info.callee.guarantees
  in
  assumptions @ guarantees

let state_range_invariant info =
  B.mk_hand
    (h_ge_int info.state_var 0)
    (h_lt_int info.state_var (List.length info.state_codes))

let lift_state_invariant parent_state info
    (invariant : Verification_model.state_invariant) =
  {
    Verification_model.state = parent_state;
    formula =
      B.mk_himp
        (h_eq_int info.state_var
           (code_of_state info invariant.state))
        (subst_hexpr info.names invariant.formula);
  }

let flatten_one (owner : Verification_model.node_model) instances =
  if
    List.exists
      (fun (step : Verification_model.program_step) ->
        String.equal step.dst_state owner.init_state)
      owner.steps
  then
    fail
      "node '%s': a composite node requires a dedicated, non-reentrant init state"
      owner.node_name;
  let instance_names = List.map fst instances in
  validate_schedule owner.node_name instance_names owner.steps;
  let infos =
    List.map
      (fun (instance_name, callee) ->
        let input_bindings, _ =
          binding_for_instance owner.node_name instance_name owner.steps
        in
        make_instance_info owner.node_name instance_name input_bindings callee)
      instances
  in
  let info_by_name =
    List.fold_left
      (fun map info -> StringMap.add info.instance_name info map)
      StringMap.empty infos
  in
  let init_instance_state =
    List.map
      (fun info ->
        mk_stmt
          (SAssign
             ( info.state_var,
               B.mk_int (code_of_state info info.callee.init_state) )))
      infos
  in
  let expand_top_stmt ~initial stmt =
    match stmt.stmt with
    | SCall (callee, args, destinations) ->
        let info =
          match StringMap.find_opt callee info_by_name with
          | Some info -> info
          | None ->
            fail "node '%s': unknown instance '%s'" owner.node_name callee
        in
        expand_call ~initial owner.node_name info args destinations
    | _ -> [ stmt ]
  in
  let steps =
    List.map
      (fun (step : Verification_model.program_step) ->
        let initial = String.equal step.src_state owner.init_state in
        let initialize =
          if initial then
            init_instance_state
          else []
        in
        {
          step with
          body_stmts =
            initialize
            @ List.concat_map
                (expand_top_stmt ~initial)
                step.body_stmts;
          elaboration_checks =
            step.elaboration_checks
            @ List.concat_map transition_checks infos;
        })
      owner.steps
  in
  let generated_locals =
    List.concat_map
      (fun info ->
        [
          { vname = info.state_var; vty = TInt };
          { vname = info.transition_var; vty = TInt };
        ]
        @ info.output_storage @ info.local_storage)
      infos
  in
  let generated_ghosts = List.concat_map (fun info -> info.ghost_storage) infos in
  let stable_parent_states =
    List.filter (fun state -> not (String.equal state owner.init_state)) owner.states
  in
  let generated_invariants =
    List.concat_map
      (fun parent_state ->
        List.concat_map
          (fun info ->
            {
              Verification_model.state = parent_state;
              formula = state_range_invariant info;
            }
            :: List.map
                 (lift_state_invariant parent_state info)
                 info.callee.state_invariants)
          infos)
      stable_parent_states
  in
  {
    owner with
    locals = owner.locals @ generated_locals;
    ghosts = owner.ghosts @ generated_ghosts;
    public_ghosts =
      owner.public_ghosts
      @ List.concat_map (fun info -> info.public_ghost_storage) infos;
    steps;
    guarantees =
      owner.guarantees
      @ List.concat_map lift_instance_guarantees infos;
    state_invariants = owner.state_invariants @ generated_invariants;
  }

let flatten_program ~instance_decls program =
  let nodes_by_name =
    List.fold_left
      (fun map (node : Verification_model.node_model) ->
        if StringMap.mem node.node_name map then
          fail "duplicate node '%s'" node.node_name;
        StringMap.add node.node_name node map)
      StringMap.empty program
  in
  let decls_by_name =
    List.fold_left
      (fun map (node_name, decls) ->
        StringMap.add node_name decls map)
      StringMap.empty instance_decls
  in
  let resolved_instances =
    StringMap.mapi
      (fun node_name node ->
        let declared =
          StringMap.find_opt node_name decls_by_name
          |> Option.value ~default:[]
        in
        resolve_instance_decls ~nodes_by_name ~declared node)
      nodes_by_name
  in
  let referenced =
    StringMap.fold
      (fun _ instances set ->
        List.fold_left
          (fun set (_, callee) -> StringSet.add callee set)
          set instances)
      resolved_instances StringSet.empty
  in
  let cache = Hashtbl.create 16 in
  let rec flatten_node stack name =
    match Hashtbl.find_opt cache name with
    | Some node -> node
    | None ->
        if List.mem name stack then
          fail "recursive node instantiation: %s"
            (String.concat " -> " (List.rev (name :: stack)));
        let node =
          match StringMap.find_opt name nodes_by_name with
          | Some node -> node
          | None -> fail "unknown node '%s'" name
        in
        let instances =
          StringMap.find_opt name resolved_instances
          |> Option.value ~default:[]
        in
        let flattened =
          if instances = [] then node
          else
            let children =
              List.map
                (fun (instance_name, callee_name) ->
                  ( instance_name,
                    flatten_node (name :: stack) callee_name ))
                instances
            in
            flatten_one node children
        in
        Kairos_to_model_validation.validate_node flattened;
        Hashtbl.add cache name flattened;
        flattened
  in
  List.iter
    (fun (node : Verification_model.node_model) ->
      ignore (flatten_node [] node.node_name))
    program;
  List.filter_map
    (fun (node : Verification_model.node_model) ->
      if StringSet.mem node.node_name referenced then None
      else Some (flatten_node [] node.node_name))
    program
