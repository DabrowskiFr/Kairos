open Ast
open Ast_builders
open Support
open Automata_atoms
open Automata_generation

module Abs = Normalized_program

let instrumentation_state_name : string = "__aut_state"
let state_ctor (i : int) : string = Printf.sprintf "Aut%d" i
let instrumentation_state_expr (i : int) : iexpr = mk_var (state_ctor i)

let instrumentation_update_stmts (atom_map : (ident * iexpr) list)
    (states : Ast.ltl list) (transitions : Spot_automaton.transition list)
    : stmt list =
  let mon = instrumentation_state_name in
  let is_true e = match e.iexpr with ILitBool true -> true | _ -> false in
  let is_false e = match e.iexpr with ILitBool false -> true | _ -> false in
  let rec chain = function
    | [] -> mk_stmt SSkip
    | (dst, cond) :: rest ->
        if is_true cond then mk_stmt (SAssign (mon, instrumentation_state_expr dst))
        else if is_false cond then chain rest
        else
          mk_stmt
            (SIf
               (cond, [ mk_stmt (SAssign (mon, instrumentation_state_expr dst)) ], [ chain rest ]))
  in
  let per_state =
    List.init (List.length states) (fun i -> i)
    |> List.map (fun i ->
           let dests =
             List.filter_map
               (fun (src, guard, dst) ->
                 if src = i then
                   let cond = recover_guard_iexpr atom_map guard in
                   Some (dst, cond)
                 else None)
               transitions
           in
           let dests = List.sort_uniq compare dests in
           if dests = [] then (i, mk_stmt SSkip) else (i, chain dests))
  in
  let branches = List.map (fun (i, body) -> (state_ctor i, [ body ])) per_state in
  match branches with [] -> [] | _ -> [ mk_stmt (SMatch (mk_var mon, branches, [])) ]

let instrumentation_assert (bad_idx : int) : stmt list = if bad_idx < 0 then [] else []

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

let inline_atoms_in_node (atom_map : (ident * iexpr) list) (n : node) : node =
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
  let inline_transition (t : transition) : transition =
    let t =
      {
        t with
        attrs =
          {
            t.attrs with
            ghost = List.map inline_stmt t.attrs.ghost;
            instrumentation = List.map inline_stmt t.attrs.instrumentation;
          };
      }
    in
    {
      t with
      guard = Option.map inline_iexpr t.guard;
      requires = List.map (Ast_provenance.map_with_origin inline_ltl) t.requires;
      ensures = List.map (Ast_provenance.map_with_origin inline_ltl) t.ensures;
      body = List.map inline_stmt t.body;
    }
  in
  let n =
    {
      n with
      semantics = { n.semantics with sem_trans = List.map inline_transition n.semantics.sem_trans };
      specification =
        {
          n.specification with
          spec_assumes = List.map inline_ltl (Ast.specification_of_node n).spec_assumes;
          spec_guarantees = List.map inline_ltl (Ast.specification_of_node n).spec_guarantees;
        };
    }
  in
  {
    n with
    attrs = { n.attrs with invariants_user = List.map inline_invariant_user n.attrs.invariants_user };
    specification =
      {
        n.specification with
        spec_invariants_state_rel =
          List.map inline_invariant_state_rel (Ast.specification_of_node n).spec_invariants_state_rel;
      };
  }

let add_initial_automaton_support_goal (n : Ast.node) : Ast.node = n

let finalize_instrumented_node ~atom_map_exprs ~user_assumes ~user_guarantees
    ~invariants_user ~invariants_state_rel (n : node) ~(trans : Abs.transition list) : node =
  let n =
    {
      n with
      semantics =
        {
          n.semantics with
          sem_locals = n.semantics.sem_locals;
          sem_trans = List.map Abs.to_ast_transition trans;
        };
      specification = { n.specification with spec_assumes = user_assumes; spec_guarantees = user_guarantees };
    }
  in
  let n =
    {
      n with
      attrs = { n.attrs with invariants_user };
      specification = { n.specification with spec_invariants_state_rel = invariants_state_rel };
    }
  in
  let n = add_initial_automaton_support_goal n in
  inline_atoms_in_node atom_map_exprs n
