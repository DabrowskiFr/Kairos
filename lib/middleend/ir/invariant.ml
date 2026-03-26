open Ast
open Fo_specs
open Fo_time
open Formula_origin

module Abs = Ir

let dedup_fo (xs : ltl list) : ltl list = List.sort_uniq compare xs

let input_names (n : Abs.node) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Abs.node) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let instrumentation_state_var = "__aut_state"

let rec fo_ltl_mentions_var (v : ident) (f : ltl) : bool =
  let hexpr_mentions_var = function
    | HNow e | HPreK (e, _) -> begin
        match e.iexpr with IVar v' -> String.equal v v' | _ -> false
      end
  in
  match f with
  | LTrue | LFalse -> false
  | LAtom (FRel (h1, _, h2)) -> hexpr_mentions_var h1 || hexpr_mentions_var h2
  | LAtom (FPred (_, hs)) -> List.exists hexpr_mentions_var hs
  | LNot a | LX a | LG a -> fo_ltl_mentions_var v a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      fo_ltl_mentions_var v a || fo_ltl_mentions_var v b

let invariant_of_state (n : Abs.node) : ident -> ltl option =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : invariant_state_rel) ->
      if List.mem inv.state n.semantics.sem_states
         && not (fo_ltl_mentions_var instrumentation_state_var inv.formula)
      then
        let existing = Hashtbl.find_opt by_state inv.state |> Option.value ~default:[] in
        Hashtbl.replace by_state inv.state (dedup_fo (inv.formula :: existing)))
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
        let ensures =
          match invariant_generation.invariant_of_state pc.product_dst.prog_state with
          | None -> pc.ensures
          | Some inv ->
              let shifted_inv = shift_ltl_forward_inputs ~is_input inv in
              add_unique_formula Invariant shifted_inv pc.ensures
        in
        if requires == pc.requires && ensures == pc.ensures then pc
        else { pc with requires; ensures })
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
