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
open Ast
open Fo_formula
open Core_syntax_builders
open Generated_names
open Temporal_support
open Logic_pretty
open Fo_specs
open Ltl_valuation

type guard = Automaton_types.guard

let guard_to_formula (g : guard) : string =
  Logic_pretty.string_of_fo g

let sanitize_ident (s : string) : string =
  (* Normalize an arbitrary string into a safe, lowercase identifier. *)
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

let make_atom_names (atom_exprs : (fo_atom * expr) list) : string list =
  (* Build stable, readable, and unique atom identifiers from expressions. *)
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
      let base = "atom_" ^ sanitize_ident (Logic_pretty.string_of_expr expr) in
      fresh base)
    atom_exprs

let inline_atoms_expr (atom_map : (ident * expr) list) (e : expr) : expr =
  (* Substitute atom variables with their underlying boolean expressions. *)
  let map = Hashtbl.create 16 in
  List.iter (fun (name, expr) -> Hashtbl.replace map name expr) atom_map;
  let rec go (e : expr) =
    match e.expr with
    | EVar name -> begin match Hashtbl.find_opt map name with Some expr -> go expr | None -> e end
    | ELitInt _ | ELitBool _ -> e
    | EUn (op, inner) -> with_expr_desc e (EUn (op, go inner))
    | EBin (op, a, b) -> with_expr_desc e (EBin (op, go a, go b))
    | ECmp (op, a, b) -> with_expr_desc e (ECmp (op, go a, go b))
  in
  go e

let recover_guard_fo (atom_map : (ident * expr) list) (g : Automaton_types.guard) : Fo_formula.t =
  let _ = atom_map in
  g

type automata_atoms = Automaton_types.automata_atoms = {
  atom_map : (fo_atom * ident) list;
  atom_named_exprs : (ident * expr) list;
}

let collect_atoms_from_ltls (n : Ast.node) ~(ltls : ltl list) :
    automata_atoms =
  let n_ast = n in
  let sem = n_ast.semantics in
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (sem.sem_inputs @ sem.sem_locals @ sem.sem_outputs)
  in
  let pre_k_map = Pre_k_collect.build_pre_k_infos n_ast in
  let inputs = List.map (fun v -> v.vname) sem.sem_inputs in
  let atoms_all = List.fold_left (fun acc f -> collect_atoms_ltl f acc) [] ltls |> List.sort_uniq compare in
  let atom_exprs, skipped =
    List.fold_left
      (fun (ok, bad) a ->
        match atom_to_expr ~inputs ~var_types ~pre_k_map a with
        | Some e -> ((a, e) :: ok, bad)
        | None -> (ok, a :: bad))
      ([], []) atoms_all
  in
  if skipped <> [] then (
    let lines =
      List.rev skipped |> List.map (fun a -> "  - " ^ Logic_pretty.string_of_fo_atom a) |> String.concat "\n"
    in
    prerr_endline "Non-translatable monitor atoms:";
    prerr_endline lines;
    failwith "Cannot build monitor: some atoms are not translatable to expr.");
  let atom_exprs = List.rev atom_exprs in
  let atom_names = make_atom_names atom_exprs in
  let atom_map = List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names in
  let atom_named_exprs = List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names in
  { atom_map; atom_named_exprs }

let collect_atoms (n : Ast.node) : automata_atoms =
  (* Instrumentation construction is guarantee-only: do not collect atoms from assumptions. *)
  let spec = Ast.specification_of_node n in
  collect_atoms_from_ltls n ~ltls:spec.spec_guarantees
