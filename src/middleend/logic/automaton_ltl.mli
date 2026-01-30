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

(** {1 LTL Normalization} *)

val nnf_ltl : ?neg:bool -> Ast.ltl -> Ast.ltl
(** Convert an LTL formula into negation normal form. *)
val simplify_ltl : Ast.ltl -> Ast.ltl
(** Simplify LTL formulas via boolean rewrites. *)
val eval_atom :
  (Ast.fo * Ast.ident) list -> (string * bool) list -> Ast.fo -> bool
(** Evaluate an atom against a valuation. *)
val progress_ltl :
  (Ast.fo * Ast.ident) list -> (string * bool) list -> Ast.ltl -> Ast.ltl
(** Progress an LTL formula through one valuation. *)
