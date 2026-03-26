open Ast
module Abs = Ir

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

let dedup_fo (xs : ltl list) : ltl list = List.sort_uniq compare xs

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
    Fo_specs.conj_ltl all

let add_initial_invariant_goal (n : Abs.node) ~(inv_of_state : ident -> ltl option) : Abs.node =
  match inv_of_state n.semantics.sem_init_state with
  | None -> n
  | Some inv ->
      if fo_ltl_mentions_var instrumentation_state_var inv then n
      else
        let existing_values =
          List.map (fun (f : Abs.contract_formula) -> f.value) n.coherency_goals
        in
        if List.mem inv existing_values then n
        else
          {
            n with
            coherency_goals =
              n.coherency_goals @ [ Abs.with_origin Formula_origin.Invariant inv ];
          }

let apply (n : Abs.node) : Abs.node =
  n |> add_initial_invariant_goal ~inv_of_state:(invariant_of_state n)

let apply_program (p : Abs.node list) : Abs.node list = List.map apply p
