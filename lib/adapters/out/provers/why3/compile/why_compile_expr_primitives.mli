(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

(** Low-level Why3 Ptree constructors used by the backend. *)

val loc : Why3.Loc.position
val ident : string -> Why3.Ptree.ident
val infix_ident : string -> Why3.Ptree.ident
val qid1 : string -> Why3.Ptree.qualid
val qdot : Why3.Ptree.qualid -> string -> Why3.Ptree.qualid
val mk_expr : Why3.Ptree.expr_desc -> Why3.Ptree.expr
val mk_term : Why3.Ptree.term_desc -> Why3.Ptree.term
val term_eq : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_neq : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_bool_binop : Why3.Dterm.dbinop -> Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_implies : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_old : Why3.Ptree.term -> Why3.Ptree.term
val apply_expr : Why3.Ptree.expr -> Why3.Ptree.expr list -> Why3.Ptree.expr
val apply_term : Why3.Ptree.term -> Why3.Ptree.term list -> Why3.Ptree.term
