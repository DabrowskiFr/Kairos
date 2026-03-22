open Ast
open Fo_specs

module Abs = Normalized_program

let is_user_contract (f : ltl_o) : bool =
  match f.origin with Some UserContract -> true | _ -> false

let user_formulas (fs : ltl_o list) : ltl_o list = List.filter is_user_contract fs
let dedup_fo (xs : ltl list) : ltl list = List.sort_uniq compare xs
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

let state_invariant_from_node (n : Abs.node) : ident -> ltl option =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : invariant_state_rel) ->
      if inv.is_eq
         && List.mem inv.state n.semantics.sem_states
         && not (fo_ltl_mentions_var instrumentation_state_var inv.formula)
      then
        let existing = Hashtbl.find_opt by_state inv.state |> Option.value ~default:[] in
        Hashtbl.replace by_state inv.state (dedup_fo (inv.formula :: existing)))
    n.specification.spec_invariants_state_rel;
  List.iter
    (fun (t : Abs.transition) ->
      let user_ens = Ast_provenance.values (user_formulas t.ensures) in
      if user_ens <> [] then
        let existing = Hashtbl.find_opt by_state t.dst |> Option.value ~default:[] in
        Hashtbl.replace by_state t.dst (dedup_fo (user_ens @ existing)))
    n.trans;
  fun st ->
    let all = Hashtbl.find_opt by_state st |> Option.value ~default:[] in
    conj_fo all

let state_invariant_from_ensures (n : Abs.node) : ident -> ltl option =
  let by_dst = Hashtbl.create 16 in
  List.iter
    (fun (t : Abs.transition) ->
      let user_ens = Ast_provenance.values (user_formulas t.ensures) in
      if user_ens <> [] then
        let existing = Hashtbl.find_opt by_dst t.dst |> Option.value ~default:[] in
        Hashtbl.replace by_dst t.dst (dedup_fo (user_ens @ existing)))
    n.trans;
  fun st ->
    let from_ensures = Hashtbl.find_opt by_dst st |> Option.value ~default:[] in
    conj_fo from_ensures

type t = {
  inv_of_state : Ast.ident -> Ast.ltl option;
  inv_from_ensures : Ast.ident -> Ast.ltl option;
}

let build (n : Abs.node) : t =
  {
    inv_of_state = state_invariant_from_node n;
    inv_from_ensures = state_invariant_from_ensures n;
  }
