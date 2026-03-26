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

(** Atom-table support for generated automata and guard recovery. *)

type guard = Automaton_types.guard
(* Semantic transition guard. *)

val guard_to_formula : guard -> string
(* Render a guard as a boolean formula string. *)

val guard_to_iexpr : guard -> Ast.iexpr
(* Convert a guard into an iexpr formula. *)

type automata_atoms = Automaton_types.automata_atoms = {
  atom_map : (Ast.fo_atom * Ast.ident) list;
  atom_named_exprs : (Ast.ident * Ast.iexpr) list;
}

val make_atom_names : (Ast.fo_atom * Ast.iexpr) list -> string list
(* Generate stable, unique atom names from atom expressions. *)

val inline_atoms_iexpr : (Ast.ident * Ast.iexpr) list -> Ast.iexpr -> Ast.iexpr
(* Inline atom variables inside a boolean expression using a name->expr map. *)

val recover_guard_iexpr : (Ast.ident * Ast.iexpr) list -> Automaton_types.guard -> Ast.iexpr
(* Identity on semantic guards; kept for compatibility at call sites. *)

val recover_guard_fo : (Ast.ident * Ast.iexpr) list -> Automaton_types.guard -> Fo_formula.t
(* Convert a semantic guard into a first-order formula. *)

val collect_atoms : Ast.node -> automata_atoms
(* Collect and validate atoms used by the monitor construction. *)

val collect_atoms_from_ltls :
  Ast.node -> ltls:Ast.ltl list -> automata_atoms
(* Collect and validate atoms for an explicit list of LTL formulas. *)
