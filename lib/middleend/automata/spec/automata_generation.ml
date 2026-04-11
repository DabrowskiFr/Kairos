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
open Automata_atoms
open Fo_specs

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
               (Logic_pretty.string_of_ltl f));
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

let build_guarantee_spec ~(atom_map : (fo_atom * ident) list) (n : Ast.node) : ltl =
  let _ = atom_map in
  let spec = Ast.specification_of_node n in
  let spec_assumes = spec.spec_assumes in
  let spec_guarantees = spec.spec_guarantees in
  List.iteri
    (fun i g ->
      validate_ltl_weak_until_positivity
        ~context:
          (Printf.sprintf "guarantee #%d of node %s" (i + 1) n.semantics.sem_nname)
        g)
    spec_guarantees;
  combine_contracts_for_monitor ~assumes:spec_assumes ~guarantees:spec_guarantees
  |> simplify_temporal_idempotence

let build_assumption_spec ~(atom_map : (fo_atom * ident) list) (n : Ast.node) : ltl =
  let _ = atom_map in
  let spec = Ast.specification_of_node n in
  List.iteri
    (fun i a ->
      validate_ltl_weak_until_positivity
        ~context:
          (Printf.sprintf "require #%d of node %s" (i + 1) n.semantics.sem_nname)
        a)
    spec.spec_assumes;
  let rec mk_and = function [] -> LTrue | [ x ] -> x | x :: xs -> LAnd (x, mk_and xs) in
  mk_and (List.rev spec.spec_assumes) |> simplify_temporal_idempotence

type automata_automaton = Automaton_types.automaton

let build_guarantee_automaton ~(atom_map : (fo_atom * ident) list)
    ~(atom_named_exprs : (ident * iexpr) list) ~(atom_names : ident list)
    (spec : ltl) : automata_automaton =
  Automaton_build.build ~atom_map ~atom_named_exprs ~atom_names spec

type automata_build = Automaton_types.automata_build = {
  atoms : Automaton_types.automata_atoms;
  guarantee_atom_names : ident list;
  guarantee_spec : ltl;
  guarantee_automaton : automata_automaton;
  assume_atoms : Automaton_types.automata_atoms option;
  assume_atom_names : ident list;
  assume_spec : ltl option;
  assume_automaton : automata_automaton option;
}
type node_builds = Automaton_types.node_builds

let build_for_node (n : Ast.node) : automata_build =
  let node_spec = Ast.specification_of_node n in
  let atoms = collect_atoms n in
  let guarantee_atom_names = List.map snd atoms.atom_map in
  let guarantee_spec = build_guarantee_spec ~atom_map:atoms.atom_map n in
  let guarantee_automaton =
    build_guarantee_automaton ~atom_map:atoms.atom_map ~atom_named_exprs:atoms.atom_named_exprs
      ~atom_names:guarantee_atom_names
      guarantee_spec
  in
  let assume_atoms, assume_atom_names, assume_spec, assume_automaton =
    if node_spec.spec_assumes = [] then (None, [], None, None)
    else
      let atoms_a = collect_atoms_from_ltls n ~ltls:node_spec.spec_assumes in
      let atom_names_a = List.map snd atoms_a.atom_map in
      let spec_a = build_assumption_spec ~atom_map:atoms_a.atom_map n in
      let automaton_a =
        build_guarantee_automaton ~atom_map:atoms_a.atom_map
          ~atom_named_exprs:atoms_a.atom_named_exprs ~atom_names:atom_names_a spec_a
      in
      (Some atoms_a, atom_names_a, Some spec_a, Some automaton_a)
  in
  {
    atoms;
    guarantee_atom_names;
    guarantee_spec;
    guarantee_automaton;
    assume_atoms;
    assume_atom_names;
    assume_spec;
    assume_automaton;
  }
