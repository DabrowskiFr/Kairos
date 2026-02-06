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
open Fo_specs

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
  let rec go (e:iexpr) =
    match e.iexpr with
    | IVar name ->
        begin match Hashtbl.find_opt map name with
        | Some expr -> go expr
        | None -> e
        end
    | ILitInt _ | ILitBool _ -> e
    | IPar inner -> with_iexpr_desc e (IPar (go inner))
    | IUn (op, inner) -> with_iexpr_desc e (IUn (op, go inner))
    | IBin (op, a, b) -> with_iexpr_desc e (IBin (op, go a, go b))
  in
  go e

type monitor_generation_atoms = {
  atom_map: (fo * ident) list;
  (* Atom formula -> generated name. *)
  atom_named_exprs: (ident * iexpr) list;
  (* Cache of atom names mapped to their boolean iexpr (FO -> iexpr conversion). *)
}

let collect_monitor_atoms (n:Ast_contracts.node) : monitor_generation_atoms =
  let n_ast = Ast_contracts.node_to_ast n in
  let var_types =
    List.map
      (fun v -> (v.vname, v.vty))
      (Ast.node_inputs n_ast @ Ast.node_locals n_ast @ Ast.node_outputs n_ast)
  in
  let fold_map = fold_map_for_node n in
  let pre_k_map = Collect.build_pre_k_infos n_ast in
  let inputs = List.map (fun v -> v.vname) (Ast.node_inputs n_ast) in
  let atoms_all =
    collect_atoms_from_node n
    |> List.sort_uniq compare
  in
  let atom_exprs, skipped =
    List.fold_left
      (fun (ok, bad) a ->
         match atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a with
         | Some e -> ((a, e) :: ok, bad)
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
  let atom_exprs = List.rev atom_exprs in
  let atom_names = make_atom_names atom_exprs in
  let atom_map =
    List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
  in
  let atom_named_exprs =
    List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names
  in
  {
    atom_map;
    atom_named_exprs;
  }
