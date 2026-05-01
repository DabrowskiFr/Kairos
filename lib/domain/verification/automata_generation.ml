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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Core_syntax
open Automaton_types
open Core_syntax_builders
open Pretty

type atom_map = (ltl_atom * ident) list

let rec collect_atoms_ltl (f : ltl) (acc : ltl_atom list) : ltl_atom list =
  match f with
  | LTrue | LFalse -> acc
  | LAtom (h1, r, h2) ->
      let atom = (h1, r, h2) in
      if List.exists (( = ) atom) acc then acc else atom :: acc
  | LNot a | LX a | LG a -> collect_atoms_ltl a acc
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      collect_atoms_ltl b (collect_atoms_ltl a acc)

let sanitize_ident (s : string) : string =
  let buf = Buffer.create (String.length s) in
  let add_underscore () =
    if Buffer.length buf = 0 || Buffer.nth buf (Buffer.length buf - 1) <> '_' then
      Buffer.add_char buf '_'
  in
  String.iter
    (fun c ->
      match c with
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> Buffer.add_char buf c
      | _ -> add_underscore ())
    s;
  let out = Buffer.contents buf in
  let out = String.lowercase_ascii out in
  let out =
    let len = String.length out in
    if len > 0 && out.[len - 1] = '_' then String.sub out 0 (len - 1) else out
  in
  let out = if out = "" then "atom" else out in
  let starts_with_digit = match out.[0] with '0' .. '9' -> true | _ -> false in
  if starts_with_digit then "atom_" ^ out else out

let make_atom_names (atom_exprs : (ltl_atom * expr) list) : string list =
  let used = Hashtbl.create 16 in
  let fresh base =
    let rec loop n =
      let name = if n = 0 then base else base ^ "_" ^ string_of_int n in
      if Hashtbl.mem used name then loop (n + 1)
      else (
        Hashtbl.add used name ();
        name)
    in
    loop 0
  in
  List.map
    (fun (_atom, expr) ->
      let base = "atom_" ^ sanitize_ident (Pretty.string_of_expr expr) in
      fresh base)
    atom_exprs

let infer_expr_type ~(var_types : (ident * ty) list) (e : expr) : ty option =
  let rec go = function
    | ELitBool _ -> Some TBool
    | ELitInt _ -> Some TInt
    | EVar x -> List.assoc_opt x var_types
    | EUn (Not, _) -> Some TBool
    | EUn (Neg, _) -> Some TInt
    | EBin (And, _, _) | EBin (Or, _, _) -> Some TBool
    | EBin (Add, _, _) | EBin (Sub, _, _) | EBin (Mul, _, _) | EBin (Div, _, _) -> Some TInt
    | ECmp (_, _, _) -> Some TBool
  in
  go e.expr

let mk_bool_eq (a : expr) (b : expr) : expr =
  mk_expr
    (EBin
       ( Or,
         mk_expr (EBin (And, a, b)),
         mk_expr (EBin (And, mk_expr (EUn (Not, a)), mk_expr (EUn (Not, b)))) ))

let mk_bool_neq (a : expr) (b : expr) : expr =
  mk_expr
    (EBin
       ( Or,
         mk_expr (EBin (And, a, mk_expr (EUn (Not, b)))),
         mk_expr (EBin (And, mk_expr (EUn (Not, a)), b)) ))

let atom_to_expr ~(inputs : ident list) ~(var_types : (ident * ty) list)
    ~(temporal_layout : Pre_k_layout.pre_k_info list)
    ((h1, r, h2) : ltl_atom) : expr option =
  let _ = inputs in
  match
    ( Pre_k_lowering.hexpr_to_expr ~inputs ~var_types ~temporal_layout h1,
      Pre_k_lowering.hexpr_to_expr ~inputs ~var_types ~temporal_layout h2 )
  with
  | Some e1, Some e2 ->
      let ty1 = infer_expr_type ~var_types e1 in
      let ty2 = infer_expr_type ~var_types e2 in
      begin match (ty1, ty2, r) with
      | Some TBool, Some TBool, REq -> Some (mk_bool_eq e1 e2)
      | Some TBool, Some TBool, RNeq -> Some (mk_bool_neq e1 e2)
      | _ -> Some (mk_expr (ECmp (r, e1, e2)))
      end
  | _ -> None

let collect_atoms_from_ltls (n : Verification_model.node_model) ~(ltls : ltl list) : atom_map =
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let temporal_layout = Pre_k_layout.build_pre_k_infos n in
  let inputs = List.map (fun v -> v.vname) n.inputs in
  let atoms_all = List.fold_left (fun acc f -> collect_atoms_ltl f acc) [] ltls |> List.sort_uniq compare in
  let atom_exprs, skipped =
    List.fold_left
      (fun (ok, bad) a ->
        match atom_to_expr ~inputs ~var_types ~temporal_layout a with
        | Some e -> ((a, e) :: ok, bad)
        | None -> (ok, a :: bad))
      ([], []) atoms_all
  in
  if skipped <> [] then (
    let lines =
      List.rev skipped
      |> List.map (fun (h1, r, h2) ->
             "  - " ^ Pretty.string_of_hexpr h1 ^ " " ^ Pretty.string_of_relop r ^ " " ^ Pretty.string_of_hexpr h2)
      |> String.concat "\n"
    in
    prerr_endline "Non-translatable monitor atoms:";
    prerr_endline lines;
    failwith "Cannot build monitor: some atoms are not translatable to expr.");
  let atom_exprs = List.rev atom_exprs in
  let atom_names = make_atom_names atom_exprs in
  List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names

let collect_atoms (n : Verification_model.node_model) : atom_map =
  collect_atoms_from_ltls n ~ltls:n.guarantees

let validate_ltl_weak_until_positivity ~(context : string) (f : ltl) : unit =
  let rec go ~(positive : bool) (g : ltl) : unit =
    match g with
    | LTrue | LFalse | LAtom _ -> ()
    | LNot a -> go ~positive:(not positive) a
    | LAnd (a, b) | LOr (a, b) ->
        go ~positive a;
        go ~positive b
    | LImp (a, b) ->
        go ~positive:(not positive) a;
        go ~positive b
    | LX a | LG a -> go ~positive a
    | LW (a, b) ->
        if not positive then
          failwith
            (Printf.sprintf
               "Unsupported LTL formula in %s: weak-until W appears in negative position: %s" context
               (Pretty.string_of_ltl f));
        go ~positive a;
        go ~positive b
  in
  go ~positive:true f

let rec simplify_temporal_idempotence (f : ltl) : ltl =
  match f with
  | LTrue | LFalse | LAtom _ -> f
  | LNot a -> LNot (simplify_temporal_idempotence a)
  | LX a -> LX (simplify_temporal_idempotence a)
  | LG a -> begin match simplify_temporal_idempotence a with LG b -> LG b | a' -> LG a' end
  | LW (a, b) -> LW (simplify_temporal_idempotence a, simplify_temporal_idempotence b)
  | LAnd (a, b) -> LAnd (simplify_temporal_idempotence a, simplify_temporal_idempotence b)
  | LOr (a, b) -> LOr (simplify_temporal_idempotence a, simplify_temporal_idempotence b)
  | LImp (a, b) -> LImp (simplify_temporal_idempotence a, simplify_temporal_idempotence b)

let combine_guarantees_for_automaton ~(assumes : ltl list) ~(guarantees : ltl list) : ltl =
  let rec mk_and = function [] -> LTrue | [ x ] -> x | x :: xs -> LAnd (x, mk_and xs) in
  let g = mk_and (List.rev guarantees) in
  let _ = assumes in
  match guarantees with [] -> LTrue | _ -> g

let build_guarantee_spec ~(atom_map : atom_map) (n : Verification_model.node_model) : ltl =
  let _ = atom_map in
  let spec_assumes = n.assumes in
  let spec_guarantees = n.guarantees in
  List.iteri
    (fun i g ->
      validate_ltl_weak_until_positivity
        ~context:
          (Printf.sprintf "guarantee #%d of node %s" (i + 1) n.node_name)
        g)
    spec_guarantees;
  combine_guarantees_for_automaton ~assumes:spec_assumes ~guarantees:spec_guarantees
  |> simplify_temporal_idempotence

let build_assumption_spec ~(atom_map : atom_map) (n : Verification_model.node_model) : ltl =
  let _ = atom_map in
  List.iteri
    (fun i a ->
      validate_ltl_weak_until_positivity
        ~context:
          (Printf.sprintf "require #%d of node %s" (i + 1) n.node_name)
        a)
    n.assumes;
  let rec mk_and = function [] -> LTrue | [ x ] -> x | x :: xs -> LAnd (x, mk_and xs) in
  mk_and (List.rev n.assumes) |> simplify_temporal_idempotence

type automata_automaton = Automaton_types.automaton

let build_guarantee_automaton
    ~(build_automaton :
       atom_map:atom_map ->
       ltl ->
       automata_automaton)
    ~(atom_map : atom_map) (spec : ltl) : automata_automaton =
  build_automaton ~atom_map spec

(* type automata_build = Automaton_types.automata_build = {
  guarantee_automaton : automata_automaton;
  assume_automaton : automata_automaton;
} *)

let build_for_node
    ~(build_automaton :
       atom_map:atom_map ->
       ltl ->
       automata_automaton)
    (n : Verification_model.node_model) : automata_spec =
  let atoms = collect_atoms n in
  let guarantee_spec = build_guarantee_spec ~atom_map:atoms n in
  let guarantee_automaton =
    build_guarantee_automaton ~build_automaton ~atom_map:atoms guarantee_spec
  in
  let trivial_assume_automaton =
    {
      Automaton_types.states = [ LTrue ];
      transitions = [ (0, mk_hbool true, 0) ];
    }
  in
  let assume_automaton =
    if n.assumes = [] then trivial_assume_automaton
    else
      let atoms_a = collect_atoms_from_ltls n ~ltls:n.assumes in
      let spec_a = build_assumption_spec ~atom_map:atoms_a n in
      build_guarantee_automaton ~build_automaton ~atom_map:atoms_a
        spec_a
  in
  { guarantee_automaton; assume_automaton }

type automata_info = {
  residual_state_count : int;
  residual_edge_count : int;
  warnings : string list;
}

let run (p : Verification_model.program_model)
    ~(build_automaton :
       atom_map:atom_map ->
       ltl ->
       automata_automaton) :
    (ident * automata_spec) list * automata_info =
  let state_count = ref 0 in
  let edge_count = ref 0 in
  let warnings = ref [] in
  let automata =
    List.map
      (fun n ->
        let build = build_for_node ~build_automaton n in
        let automaton = build.guarantee_automaton in
        state_count := !state_count + List.length automaton.states;
        edge_count := !edge_count + List.length automaton.transitions;
        (n.node_name, build))
      p
  in
  let info =
    {
      residual_state_count = !state_count;
      residual_edge_count = !edge_count;
      warnings = List.rev !warnings;
    }
  in
  (automata, info)
