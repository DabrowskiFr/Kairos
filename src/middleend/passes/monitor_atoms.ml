(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

open Ast
open Support
open Specs

let sanitize_ident (s:string) : string =
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
  let starts_with_digit =
    match out.[0] with '0' .. '9' -> true | _ -> false
  in
  if starts_with_digit then "atom_" ^ out else out

let make_atom_names (atom_exprs:(fo * iexpr) list) : string list =
  (* Build stable, readable, and unique atom identifiers from expressions. *)
  let used = Hashtbl.create 16 in
  let fresh base =
    let rec loop n =
      let name = if n = 0 then base else base ^ "_" ^ string_of_int n in
      if Hashtbl.mem used name then loop (n + 1)
      else (Hashtbl.add used name (); name)
    in
    loop 0
  in
  List.map
    (fun (_atom, expr) ->
       let base =
         "atom_" ^ sanitize_ident (Support.string_of_iexpr expr)
       in
       fresh base)
    atom_exprs

let inline_atoms_iexpr (atom_map:(ident * iexpr) list) (e:iexpr) : iexpr =
  (* Substitute atom variables with their underlying boolean expressions. *)
  let map = Hashtbl.create 16 in
  List.iter (fun (name, expr) -> Hashtbl.replace map name expr) atom_map;
  let rec go = function
    | IVar name ->
        begin match Hashtbl.find_opt map name with
        | Some expr -> expr
        | None -> IVar name
        end
    | ILitInt _ | ILitBool _ as e -> e
    | IPar e -> IPar (go e)
    | IUn (op, e) -> IUn (op, go e)
    | IBin (op, a, b) -> IBin (op, go a, go b)
  in
  go e

type monitor_atoms = {
  var_types: (ident * ty) list;
  (* Types for all node variables (inputs/locals/outputs). *)
  fold_map: (hexpr * ident) list;
  (* Map from fold hexpr to its accumulator variable name. *)
  atom_names: ident list;
  (* Fresh, unique names assigned to each atom. *)
  atom_map: (fo * ident) list;
  (* Map from atom formula to its generated name. *)
  atom_name_to_fo: (ident * fo) list;
  (* Map from atom name back to the original formula. *)
  atom_named_exprs: (ident * iexpr) list;
  (* Map from atom name to the boolean iexpr it represents. *)
}

let collect_monitor_atoms (n:node) : monitor_atoms =
  (* Collect and validate atom mappings needed for monitor construction. *)
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let fold_map = fold_map_for_node n in
  let pre_k_map = Collect.build_pre_k_infos n in
  let inputs = List.map (fun v -> v.vname) n.inputs in
  let atoms_all =
    collect_atoms_from_node n
    |> List.sort_uniq compare
  in
  let atoms, skipped =
    List.fold_left
      (fun (ok, bad) a ->
         match atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a with
         | Some _ -> (a :: ok, bad)
         | None -> (ok, a :: bad))
      ([], [])
      atoms_all
  in
  if skipped <> [] then (
    let lines =
      List.rev skipped
      |> List.map (fun a -> "  - " ^ Support.string_of_fo a)
      |> String.concat "\n"
    in
    prerr_endline "Non-translatable monitor atoms:";
    prerr_endline lines;
    failwith "Cannot build monitor: some atoms are not translatable to iexpr."
  );
  let atom_exprs =
    List.filter_map
      (fun a ->
         match atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a with
         | Some e -> Some (a, e)
         | None -> None)
      atoms
  in
  let atom_names = make_atom_names atom_exprs in
  let atom_map =
    List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
  in
  let atom_name_to_fo =
    List.map2 (fun (a, _) name -> (name, a)) atom_exprs atom_names
  in
  let atom_named_exprs =
    List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names
  in
  {
    var_types;
    fold_map;
    atom_names;
    atom_map;
    atom_name_to_fo;
    atom_named_exprs;
  }
