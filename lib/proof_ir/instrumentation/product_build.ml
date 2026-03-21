open Ast
open Support
open Fo_specs
open Automata_atoms
open Ltl_valuation

module Abs = Abstract_model
module PT = Product_types

type automaton_view = {
  states : Ast.ltl list;
  grouped : Spot_automaton.transition list;
  atom_map_exprs : (ident * iexpr) list;
  bad_idx : int;
}

type analysis = {
  exploration : PT.exploration;
  assume_bad_idx : int;
  guarantee_bad_idx : int;
  guarantee_state_labels : string list;
  assume_state_labels : string list;
  guarantee_grouped_edges : Spot_automaton.transition list;
  assume_grouped_edges : Spot_automaton.transition list;
  guarantee_atom_map_exprs : (ident * iexpr) list;
  assume_atom_map_exprs : (ident * iexpr) list;
}

let fo_of_iexpr (e : iexpr) : ltl = iexpr_to_fo_with_atoms [] e

let automaton_guard_fo ~(atom_map_exprs : (ident * iexpr) list) (g : Automaton_types.guard) : ltl =
  let recovered = recover_guard_fo atom_map_exprs g in
  let simplified = Fo_simplifier.simplify_fo recovered in
  match (g, simplified) with
  | [], _ -> LFalse
  | _ :: _, LFalse ->
      (* Some temporal guards are conservatively recovered through atom
         expressions and may collapse to [false] even though the original DNF
         guard is not empty. Keep the unsimplified formula so the product
         exploration stays conservative and does not prune potentially-live
         steps. *)
      recovered
  | _ -> simplified

let program_guard_fo (t : Abs.transition) : ltl =
  (* Program guards are normalized before overlap checks so they are compared at
     the same boolean level as recovered automaton guards. *)
  match t.guard with None -> LTrue | Some g -> fo_of_iexpr g |> Fo_simplifier.simplify_fo

type lit = { var : ident; cst : string; is_pos : bool }

let lit_of_rel (h1 : hexpr) (r : relop) (h2 : hexpr) : lit option =
  let mk ?(is_pos = true) v c = Some { var = v; cst = c; is_pos } in
  match (h1, r, h2) with
  | HNow a, REq, HNow b -> begin
      match (a.iexpr, b.iexpr) with
      | IVar v, ILitInt i -> mk v (string_of_int i)
      | ILitInt i, IVar v -> mk v (string_of_int i)
      | IVar v, ILitBool b -> mk v (if b then "true" else "false")
      | ILitBool b, IVar v -> mk v (if b then "true" else "false")
      | _ -> None
    end
  | HNow a, RNeq, HNow b -> begin
      match (a.iexpr, b.iexpr) with
      | IVar v, ILitInt i -> mk ~is_pos:false v (string_of_int i)
      | ILitInt i, IVar v -> mk ~is_pos:false v (string_of_int i)
      | IVar v, ILitBool b -> mk ~is_pos:false v (if b then "true" else "false")
      | ILitBool b, IVar v -> mk ~is_pos:false v (if b then "true" else "false")
      | _ -> None
    end
  | _ -> None

let rec conj_lits (f : ltl) : lit list option =
  match f with
  | LTrue -> Some []
  | LAtom (FRel (h1, r, h2)) -> Option.map (fun l -> [ l ]) (lit_of_rel h1 r h2)
  | LNot x -> begin
      match x with
      | LAtom (FRel (h1, REq, h2)) -> Option.map (fun l -> [ { l with is_pos = false } ]) (lit_of_rel h1 REq h2)
      | _ -> None
    end
  | LAnd (a, b) -> begin
      match (conj_lits a, conj_lits b) with
      | Some la, Some lb -> Some (la @ lb)
      | _ -> None
    end
  | _ -> None

let disj_conjs (f : ltl) : lit list list option =
  let rec go = function LOr (a, b) -> go a @ go b | x -> [ x ] in
  let xs = go f |> List.map conj_lits in
  List.fold_right
    (fun x acc -> Option.bind x (fun v -> Option.map (fun r -> v :: r) acc))
    xs (Some [])

let lits_consistent (a : lit list) (b : lit list) : bool =
  let pos = Hashtbl.create 16 in
  let neg = Hashtbl.create 16 in
  let add_lit l =
    if l.is_pos then (
      let prev = Hashtbl.find_opt pos l.var |> Option.value ~default:[] in
      if not (List.mem l.cst prev) then Hashtbl.replace pos l.var (l.cst :: prev))
    else (
      let prev = Hashtbl.find_opt neg l.var |> Option.value ~default:[] in
      if not (List.mem l.cst prev) then Hashtbl.replace neg l.var (l.cst :: prev))
  in
  List.iter add_lit (a @ b);
  let ok = ref true in
  Hashtbl.iter
    (fun v vals ->
      let unique_vals = List.sort_uniq String.compare vals in
      let neg_vals =
        Hashtbl.find_opt neg v |> Option.value ~default:[] |> List.sort_uniq String.compare
      in
      if List.length unique_vals > 1 then ok := false;
      if List.exists (fun c -> List.mem c neg_vals) unique_vals then ok := false)
    pos;
  !ok

let fo_overlap_conservative (a : ltl) (b : ltl) : bool =
  (* Conservative satisfiability check on already-normalized guards.
     This intentionally keeps program, assumption, and guarantee guards separate:
     it only decides whether two guards may overlap, it does not merge them. *)
  match (disj_conjs a, disj_conjs b) with
  | Some da, Some db ->
      List.exists (fun ca -> List.exists (fun cb -> lits_consistent ca cb) db) da
  | _ -> true

let first_false_idx (states : Ast.ltl list) : int =
  let rec loop i = function
    | [] -> -1
    | LFalse :: _ -> i
    | _ :: tl -> loop (i + 1) tl
  in
  loop 0 states

let make_assume_view (build : Automata_generation.automata_build) : automaton_view =
  match (build.assume_automaton, build.assume_atoms) with
  | Some automaton, Some atoms ->
      {
        states = automaton.states;
        grouped = automaton.grouped;
        atom_map_exprs = atoms.atom_named_exprs;
        bad_idx = first_false_idx automaton.states;
      }
  | _ ->
      {
        states = [ LTrue ];
        grouped = [ (0, [ [] ], 0) ];
        atom_map_exprs = [];
        bad_idx = -1;
      }

let make_guarantee_view (build : Automata_generation.automata_build) : automaton_view =
  {
    states = build.automaton.states;
    grouped = build.automaton.grouped;
    atom_map_exprs = build.atoms.atom_named_exprs;
    bad_idx = first_false_idx build.automaton.states;
  }

let node_outgoing (n : Abs.node) : (ident, Abs.transition list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (t : Abs.transition) ->
      let prev = Hashtbl.find_opt tbl t.src |> Option.value ~default:[] in
      Hashtbl.replace tbl t.src (t :: prev))
    n.trans;
  tbl

let automaton_outgoing (view : automaton_view) : (int * Spot_automaton.transition list) list =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (((src, _guard, _dst) as edge) : Spot_automaton.transition) ->
      let prev = Hashtbl.find_opt tbl src |> Option.value ~default:[] in
      Hashtbl.replace tbl src (edge :: prev))
    view.grouped;
  Hashtbl.fold (fun src edges acc -> (src, edges) :: acc) tbl []

let edges_from_outgoing outgoing idx =
  List.assoc_opt idx outgoing |> Option.value ~default:[]

let state_label i states =
  match List.nth_opt states i with
  | Some s -> string_of_ltl s
  | None -> Printf.sprintf "<state %d?>" i

let classify_step ~(assume_bad_idx : int) ~(guarantee_bad_idx : int) (dst : PT.product_state) :
    PT.step_class =
  if assume_bad_idx >= 0 && dst.assume_state = assume_bad_idx then PT.Bad_assumption
  else if guarantee_bad_idx >= 0 && dst.guarantee_state = guarantee_bad_idx then PT.Bad_guarantee
  else PT.Safe

let analyze_node ~(build : Automata_generation.automata_build) ~(node : Abs.node) : analysis =
  let assume = make_assume_view build in
  let guarantee = make_guarantee_view build in
  let prog_outgoing = node_outgoing node in
  let assume_outgoing = automaton_outgoing assume in
  let guarantee_outgoing = automaton_outgoing guarantee in
  let initial_state =
    { PT.prog_state = node.semantics.sem_init_state; assume_state = 0; guarantee_state = 0 }
  in
  let seen = Hashtbl.create 64 in
  let q = Queue.create () in
  let states_rev = ref [] in
  let steps_rev = ref [] in
  let pruned_rev = ref [] in
  let push_state st =
    if not (Hashtbl.mem seen st) then (
      Hashtbl.add seen st ();
      states_rev := st :: !states_rev;
      Queue.add st q)
  in
  let mk_pruned ~src ~prog_transition ~prog_guard ~assume_edge ~assume_src ~assume_dst ~assume_guard
      ~guarantee_edge ~guarantee_src ~guarantee_dst ~guarantee_guard ~reason =
    {
      PT.src;
      prog_transition;
      prog_guard;
      assume_edge;
      assume_src;
      assume_dst;
      assume_guard;
      guarantee_edge;
      guarantee_src;
      guarantee_dst;
      guarantee_guard;
      reason;
    }
  in
  push_state initial_state;
  while not (Queue.is_empty q) do
    let src = Queue.take q in
    let prog_edges = Hashtbl.find_opt prog_outgoing src.prog_state |> Option.value ~default:[] in
    let assume_edges = edges_from_outgoing assume_outgoing src.assume_state in
    let guarantee_edges = edges_from_outgoing guarantee_outgoing src.guarantee_state in
    List.iter
      (fun (prog_transition : Abs.transition) ->
        let prog_guard = program_guard_fo prog_transition in
        List.iter
          (fun (((_assume_src, assume_guard_raw, assume_dst) as assume_edge) : Spot_automaton.transition) ->
            let assume_guard = automaton_guard_fo ~atom_map_exprs:assume.atom_map_exprs assume_guard_raw in
            List.iter
              (fun (((_guarantee_src, guarantee_guard_raw, guarantee_dst) as guarantee_edge) :
                     Spot_automaton.transition) ->
                let guarantee_guard =
                  automaton_guard_fo ~atom_map_exprs:guarantee.atom_map_exprs guarantee_guard_raw
                in
                if not (fo_overlap_conservative prog_guard assume_guard) then
                  pruned_rev :=
                    mk_pruned ~src ~prog_transition ~prog_guard ~assume_edge
                      ~assume_src:src.assume_state ~assume_dst ~assume_guard ~guarantee_edge
                      ~guarantee_src:src.guarantee_state ~guarantee_dst
                      ~guarantee_guard ~reason:PT.Incompatible_program_assumption
                    :: !pruned_rev
                else if not (fo_overlap_conservative prog_guard guarantee_guard) then
                  pruned_rev :=
                    mk_pruned ~src ~prog_transition ~prog_guard ~assume_edge
                      ~assume_src:src.assume_state ~assume_dst ~assume_guard ~guarantee_edge
                      ~guarantee_src:src.guarantee_state ~guarantee_dst
                      ~guarantee_guard ~reason:PT.Incompatible_program_guarantee
                    :: !pruned_rev
                else if not (fo_overlap_conservative assume_guard guarantee_guard) then
                  pruned_rev :=
                    mk_pruned ~src ~prog_transition ~prog_guard ~assume_edge
                      ~assume_src:src.assume_state ~assume_dst ~assume_guard ~guarantee_edge
                      ~guarantee_src:src.guarantee_state ~guarantee_dst
                      ~guarantee_guard ~reason:PT.Incompatible_assumption_guarantee
                    :: !pruned_rev
                else
                  let dst =
                    {
                      PT.prog_state = prog_transition.dst;
                      assume_state = assume_dst;
                      guarantee_state = guarantee_dst;
                    }
                  in
                  let step_class =
                    classify_step ~assume_bad_idx:assume.bad_idx ~guarantee_bad_idx:guarantee.bad_idx dst
                  in
                  let step =
                    {
                      PT.src;
                      dst;
                      prog_transition;
                      prog_guard;
                      assume_edge;
                      assume_guard;
                      guarantee_edge;
                      guarantee_guard;
                      step_class;
                    }
                  in
                  steps_rev := step :: !steps_rev;
                  push_state dst)
              guarantee_edges)
          assume_edges)
      prog_edges
  done;
  {
    exploration =
      {
        PT.initial_state;
        states = List.sort_uniq PT.compare_state (List.rev !states_rev);
        steps = List.rev !steps_rev;
        pruned_steps = List.rev !pruned_rev;
      };
    assume_bad_idx = assume.bad_idx;
    guarantee_bad_idx = guarantee.bad_idx;
    guarantee_state_labels = List.mapi (fun i _ -> state_label i guarantee.states) guarantee.states;
    assume_state_labels = List.mapi (fun i _ -> state_label i assume.states) assume.states;
    guarantee_grouped_edges = guarantee.grouped;
    assume_grouped_edges = assume.grouped;
    guarantee_atom_map_exprs = guarantee.atom_map_exprs;
    assume_atom_map_exprs = assume.atom_map_exprs;
  }
