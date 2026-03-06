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

open Ast
open Automaton_core
open Fo_specs

let validate_ltl_weak_until_positivity ~(context : string) (f : fo_ltl) : unit =
  let rec go ~(positive : bool) (g : fo_ltl) : unit =
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
               (Support.string_of_ltl f));
        go ~positive a;
        go ~positive b
  in
  go ~positive:true f

let rec simplify_temporal_idempotence (f : fo_ltl) : fo_ltl =
  match f with
  | LTrue | LFalse | LAtom _ -> f
  | LNot a -> LNot (simplify_temporal_idempotence a)
  | LX a -> LX (simplify_temporal_idempotence a)
  | LG a -> begin match simplify_temporal_idempotence a with LG b -> LG b | a' -> LG a' end
  | LW (a, b) -> LW (simplify_temporal_idempotence a, simplify_temporal_idempotence b)
  | LAnd (a, b) -> LAnd (simplify_temporal_idempotence a, simplify_temporal_idempotence b)
  | LOr (a, b) -> LOr (simplify_temporal_idempotence a, simplify_temporal_idempotence b)
  | LImp (a, b) -> LImp (simplify_temporal_idempotence a, simplify_temporal_idempotence b)

let build_monitor_spec ~(atom_map : (fo * ident) list) (n : Ast.node) : fo_ltl =
  let _ = atom_map in
  let spec_assumes = n.assumes in
  let spec_guarantees = n.guarantees in
  List.iteri
    (fun i g ->
      validate_ltl_weak_until_positivity ~context:(Printf.sprintf "guarantee #%d of node %s" (i + 1) n.nname) g)
    spec_guarantees;
  (* Assumptions are not monitorized (they remain backend proof hypotheses). *)
  combine_contracts_for_monitor ~assumes:spec_assumes ~guarantees:spec_guarantees
  |> simplify_temporal_idempotence |> simplify_ltl

let build_assumption_spec ~(atom_map : (fo * ident) list) (n : Ast.node) : fo_ltl =
  let _ = atom_map in
  List.iteri
    (fun i a ->
      validate_ltl_weak_until_positivity ~context:(Printf.sprintf "require #%d of node %s" (i + 1) n.nname) a)
    n.assumes;
  let rec mk_and = function [] -> LTrue | [ x ] -> x | x :: xs -> LAnd (x, mk_and xs) in
  mk_and (List.rev n.assumes) |> simplify_temporal_idempotence |> simplify_ltl
