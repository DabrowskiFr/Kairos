open Ast
open Fo_specs
open Fo_time
open Formula_origin
open Ast_pretty

module Abs = Ir

let dedup_fo (xs : ltl list) : ltl list = List.sort_uniq compare xs

let input_names (n : Abs.node) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Abs.node) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let rec iexpr_mentions_current_input ~(is_input : ident -> bool) (e : Ast.iexpr) =
  match e.iexpr with
  | IVar name -> is_input name
  | ILitInt _ | ILitBool _ -> false
  | IPar inner | IUn (_, inner) -> iexpr_mentions_current_input ~is_input inner
  | IBin (_, a, b) ->
      iexpr_mentions_current_input ~is_input a || iexpr_mentions_current_input ~is_input b

let hexpr_mentions_current_input ~(is_input : ident -> bool) = function
  | HNow e -> iexpr_mentions_current_input ~is_input e
  | HPreK _ -> false

let rec ltl_mentions_current_input ~(is_input : ident -> bool) (f : Ast.ltl) =
  match f with
  | LTrue | LFalse -> false
  | LAtom (FRel (a, _, b)) ->
      hexpr_mentions_current_input ~is_input a || hexpr_mentions_current_input ~is_input b
  | LAtom (FPred (_, hs)) -> List.exists (hexpr_mentions_current_input ~is_input) hs
  | LNot inner | LX inner | LG inner -> ltl_mentions_current_input ~is_input inner
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      ltl_mentions_current_input ~is_input a || ltl_mentions_current_input ~is_input b

let reject_current_input_invariant ~(node : Abs.node) (inv : invariant_state_rel) : unit =
  let is_input = is_input_of_node node in
  if ltl_mentions_current_input ~is_input inv.formula then
    failwith
      (Printf.sprintf
         "State invariant for node %s in state %s mentions a current input (HNow on an input), \
          which is forbidden for node-entry invariants: %s"
         node.semantics.sem_nname inv.state (string_of_ltl inv.formula))

let invariant_of_state (n : Abs.node) : ident -> ltl option =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : invariant_state_rel) ->
      if List.mem inv.state n.semantics.sem_states then (
        reject_current_input_invariant ~node:n inv;
        let existing = Hashtbl.find_opt by_state inv.state |> Option.value ~default:[] in
        Hashtbl.replace by_state inv.state (dedup_fo (inv.formula :: existing))))
    n.source_info.state_invariants;
  fun st ->
    let all = Hashtbl.find_opt by_state st |> Option.value ~default:[] in
    conj_ltl all

type t = {
  invariant_of_state : Ast.ident -> Ast.ltl option;
}

let build ~(node : Abs.node) : t = { invariant_of_state = invariant_of_state node }

let add_unique_formula (origin : Formula_origin.t) (f : ltl)
    (xs : Abs.contract_formula list) : Abs.contract_formula list =
  if List.exists (fun (x : Abs.contract_formula) -> x.value = f) xs then xs
  else xs @ [ Abs.with_origin origin f ]

let apply ~(invariant_generation : t) (n : Abs.node) : Abs.node =
  let is_input = is_input_of_node n in
  let product_transitions =
    List.map
      (fun (pc : Abs.product_contract) ->
        let requires =
          match invariant_generation.invariant_of_state pc.product_src.prog_state with
          | None -> pc.requires
          | Some inv -> add_unique_formula Invariant inv pc.requires
        in
        let cases =
          List.map
            (fun (case : Abs.product_case) ->
              match invariant_generation.invariant_of_state case.product_dst.prog_state with
              | None -> case
              | Some inv ->
                  let shifted_inv = shift_ltl_backward_inputs ~is_input inv in
                  let ensures = add_unique_formula Invariant shifted_inv case.ensures in
                  if ensures == case.ensures then case else { case with ensures })
            pc.cases
        in
        if requires == pc.requires && cases == pc.cases then pc
        else Abs.refresh_safe_summary { pc with requires; cases })
      n.product_transitions
  in
  { n with product_transitions }

let build_program (p : Abs.node list) : (Ast.ident * t) list =
  List.map (fun (n : Abs.node) -> (n.semantics.sem_nname, build ~node:n)) p

let apply_program ~(invariant_generations : (Ast.ident * t) list) (p : Abs.node list) :
    Abs.node list =
  List.map
    (fun (n : Abs.node) ->
      let invariant_generation =
        match List.assoc_opt n.semantics.sem_nname invariant_generations with
        | Some ig -> ig
        | None ->
            failwith
              (Printf.sprintf "Missing invariant generation for normalized node %s"
                 n.semantics.sem_nname)
      in
      apply ~invariant_generation n)
    p
