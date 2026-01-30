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

type monitor_atoms = {
  atom_map: (Ast.fo * Ast.ident) list;
  atom_named_exprs: (Ast.ident * Ast.iexpr) list;
}

val make_atom_names : (Ast.fo * Ast.iexpr) list -> string list
(** Generate stable, unique atom names from atom expressions. *)

val inline_atoms_iexpr : (Ast.ident * Ast.iexpr) list -> Ast.iexpr -> Ast.iexpr
(** Inline atom variables inside a boolean expression using a name->expr map. *)

val collect_monitor_atoms : Ast.node -> monitor_atoms
(** Collect and validate atoms used by the monitor construction. *)
