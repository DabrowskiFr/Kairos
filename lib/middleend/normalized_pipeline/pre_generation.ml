open Ast
open Fo_time

module Abs = Normalized_program

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

let shift_ltl_backward_inputs ~(is_input : ident -> bool) (f : ltl) : ltl =
  match f with
  | LAtom a -> LAtom (shift_fo_backward_inputs ~is_input a)
  | _ -> f

let add_state_invariants_in_spec (n : Abs.node) ~(inv_of_state : ident -> ltl option) : Abs.node =
  let existing = n.specification.spec_invariants_state_rel in
  let has_inv st f =
    List.exists (fun inv -> inv.is_eq && inv.state = st && inv.formula = f) existing
  in
  let extra =
    n.semantics.sem_states
    |> List.filter_map (fun st ->
           match inv_of_state st with
           | None -> None
           | Some f when has_inv st f -> None
           | Some f -> Some { is_eq = true; state = st; formula = f })
  in
  if extra = [] then n
  else
    {
      n with
      specification =
        { n.specification with spec_invariants_state_rel = existing @ extra };
    }

let inject_state_invariant_contracts (n : Abs.node) ~(inv_of_state : ident -> ltl option) : Abs.node =
  let input_names = List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs in
  let is_input x = List.mem x input_names in
  let shift_inv inv = shift_ltl_backward_inputs ~is_input inv in
  let add_unique_formula (origin : Formula_origin.t) (f : ltl) (xs : Abs.contract_formula list) :
      Abs.contract_formula list =
    if List.exists (fun (x : Abs.contract_formula) -> x.value = f) xs then xs
    else xs @ [ Abs.with_origin origin f ]
  in
  let trans =
    List.map
      (fun (t : Abs.transition) ->
        let requires =
          match inv_of_state t.src with
          | None -> t.requires
          | Some inv -> add_unique_formula Formula_origin.Coherency inv t.requires
        in
        let ensures =
          match inv_of_state t.dst with
          | None -> t.ensures
          | Some inv -> add_unique_formula Formula_origin.Coherency (shift_inv inv) t.ensures
        in
        if requires == t.requires && ensures == t.ensures then t else { t with requires; ensures })
      n.trans
  in
  { n with trans }

let add_initial_invariant_goal (n : Abs.node) ~(inv_of_state : ident -> ltl option) : Abs.node =
  let input_names = List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs in
  let is_input x = List.mem x input_names in
  match inv_of_state n.semantics.sem_init_state with
  | None -> n
  | Some inv ->
      let init_goal = shift_ltl_backward_inputs ~is_input inv in
      if fo_ltl_mentions_var instrumentation_state_var init_goal then n
      else
        let existing_values = List.map (fun (f : Abs.contract_formula) -> f.value) n.coherency_goals in
        if List.mem init_goal existing_values then n
        else
          {
            n with
            coherency_goals =
              n.coherency_goals @ [ Abs.with_origin Formula_origin.Coherency init_goal ];
          }

let apply ~(post_generation : Post_generation.t) (n : Abs.node) : Abs.node =
  n
  |> inject_state_invariant_contracts ~inv_of_state:post_generation.inv_from_ensures
  |> add_state_invariants_in_spec ~inv_of_state:post_generation.inv_of_state
  |> add_initial_invariant_goal ~inv_of_state:post_generation.inv_of_state
