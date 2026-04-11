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

(** Atom-table support for the monitor-style automata construction.

    This module is responsible for:
    - collecting first-order atoms from temporal formulas;
    - assigning stable names to these atoms;
    - recovering readable guards from automaton transitions. *)

open Core_syntax
(** Guard type used on automaton transitions. *)
type guard = Automaton_types.guard

val guard_to_formula : guard -> string
(** Pretty-print a transition guard as a first-order boolean formula. *)

(** Atom tables shared by the automata-generation pipeline.

    - [atom_map] associates each semantic first-order atom with its generated
      name;
    - [atom_named_exprs] stores the corresponding named boolean expressions. *)
type automata_atoms = Automaton_types.automata_atoms = {
  atom_map : (Core_syntax.fo_atom * Core_syntax.ident) list;
  atom_named_exprs : (Core_syntax.ident * Core_syntax.expr) list;
}

val make_atom_names : (Core_syntax.fo_atom * Core_syntax.expr) list -> string list
(** [make_atom_names atoms] generates stable, readable, and unique names for the
    given atoms, preserving the input order. *)

val inline_atoms_expr : (Core_syntax.ident * Core_syntax.expr) list -> Core_syntax.expr -> Core_syntax.expr
(** [inline_atoms_expr defs expr] replaces atom variables occurring in [expr]
    by their underlying boolean expressions. *)

val recover_guard_fo : (Core_syntax.ident * Core_syntax.expr) list -> Automaton_types.guard -> Core_syntax.hexpr
(** Convert an automaton guard back to a first-order formula suitable for
    downstream rendering and export. *)

val collect_atoms : Ast.node -> automata_atoms
(** Collect all atoms needed by the guarantee-monitor construction of one node.

    This entry point is intentionally guarantee-focused: assumptions are ignored
    here and handled separately when needed. *)

val collect_atoms_from_ltls :
  Ast.node -> ltls:ltl list -> automata_atoms
(** Collect atoms for the explicit list of temporal formulas [ltls].

    The function fails when one of the extracted atoms cannot be translated to a
    boolean expression accepted by the automata construction pipeline. *)
