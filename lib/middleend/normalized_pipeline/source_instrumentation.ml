open Ast
open Ast_builders
open Support
open Automata_atoms
open Automata_generation

module Abs = Normalized_program

let instrumentation_state_name : string = "__aut_state"
let state_ctor (i : int) : string = Printf.sprintf "Aut%d" i
let instrumentation_state_expr (i : int) : iexpr = mk_var (state_ctor i)

let inline_fo_atoms (atom_map : (ident * iexpr) list) (f : fo) : fo =
  let tbl = Hashtbl.create 16 in
  List.iter (fun (id, ex) -> Hashtbl.replace tbl id ex) atom_map;
  let rec inline_iexpr (e : iexpr) =
    match e.iexpr with
    | IVar id -> begin
        match Hashtbl.find_opt tbl id with Some ex -> inline_iexpr ex | None -> e
      end
    | ILitInt _ | ILitBool _ -> e
    | IPar inner -> with_iexpr_desc e (IPar (inline_iexpr inner))
    | IUn (op, inner) -> with_iexpr_desc e (IUn (op, inline_iexpr inner))
    | IBin (op, a, b) -> with_iexpr_desc e (IBin (op, inline_iexpr a, inline_iexpr b))
  in
  let rec inline_hexpr = function
    | HNow e -> HNow (inline_iexpr e)
    | HPreK (e, k) -> HPreK (inline_iexpr e, k)
  in
  match f with
  | FRel (h1, r, h2) -> FRel (inline_hexpr h1, r, inline_hexpr h2)
  | FPred (id, hs) -> FPred (id, List.map inline_hexpr hs)

let inline_atoms_in_node (atom_map : (ident * iexpr) list) (n : Abs.node) : Abs.node =
  let inline_iexpr = inline_atoms_iexpr atom_map in
  let inline_hexpr = function
    | HNow e -> HNow (inline_iexpr e)
    | HPreK (e, k) -> HPreK (inline_iexpr e, k)
  in
  let inline_fo = inline_fo_atoms atom_map in
  let rec inline_ltl = function
    | (LTrue | LFalse) as f -> f
    | LAtom a -> LAtom (inline_fo a)
    | LNot a -> LNot (inline_ltl a)
    | LAnd (a, b) -> LAnd (inline_ltl a, inline_ltl b)
    | LOr (a, b) -> LOr (inline_ltl a, inline_ltl b)
    | LImp (a, b) -> LImp (inline_ltl a, inline_ltl b)
    | LX a -> LX (inline_ltl a)
    | LG a -> LG (inline_ltl a)
    | LW (a, b) -> LW (inline_ltl a, inline_ltl b)
  in
  let rec inline_stmt (s : stmt) =
    match s.stmt with
    | SAssign (id, e) -> with_stmt_desc s (SAssign (id, inline_iexpr e))
    | SIf (c, t, e) ->
        with_stmt_desc s (SIf (inline_iexpr c, List.map inline_stmt t, List.map inline_stmt e))
    | SMatch (e, cases, dflt) ->
        let cases = List.map (fun (id, body) -> (id, List.map inline_stmt body)) cases in
        with_stmt_desc s (SMatch (inline_iexpr e, cases, List.map inline_stmt dflt))
    | SSkip -> with_stmt_desc s SSkip
    | SCall (id, args, outs) -> with_stmt_desc s (SCall (id, List.map inline_iexpr args, outs))
  in
  let inline_invariant_user (inv : invariant_user) : invariant_user =
    { inv with inv_expr = inline_hexpr inv.inv_expr }
  in
  let inline_invariant_state_rel (inv : invariant_state_rel) : invariant_state_rel =
    { inv with formula = inline_ltl inv.formula }
  in
  let inline_transition (t : Abs.transition) : Abs.transition =
    {
      t with
      guard = Option.map inline_iexpr t.guard;
      requires = List.map (Abs.map_formula inline_ltl) t.requires;
      ensures = List.map (Abs.map_formula inline_ltl) t.ensures;
      body = List.map inline_stmt t.body;
    }
  in
  let n =
    {
      n with
      trans = List.map inline_transition n.trans;
      specification =
        {
          n.specification with
          spec_assumes = List.map inline_ltl n.specification.spec_assumes;
          spec_guarantees = List.map inline_ltl n.specification.spec_guarantees;
        };
    }
  in
  {
    n with
    user_invariants = List.map inline_invariant_user n.user_invariants;
    specification =
      {
        n.specification with
        spec_invariants_state_rel =
          List.map inline_invariant_state_rel n.specification.spec_invariants_state_rel;
      };
  }

let add_initial_automaton_support_goal (n : Abs.node) : Abs.node = n

let finalize_instrumented_node ~atom_map_exprs ~user_assumes ~user_guarantees
    ~invariants_user ~invariants_state_rel (n : Abs.node) ~(trans : Abs.transition list) : Abs.node =
  let n =
    {
      n with
      trans;
      specification = { n.specification with spec_assumes = user_assumes; spec_guarantees = user_guarantees };
    }
  in
  let n =
    {
      n with
      user_invariants = invariants_user;
      specification = { n.specification with spec_invariants_state_rel = invariants_state_rel };
    }
  in
  let n = add_initial_automaton_support_goal n in
  inline_atoms_in_node atom_map_exprs n
