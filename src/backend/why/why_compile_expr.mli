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

(** {1 Term Compilation} *)

(** Predicate for mon state ctor. *)
val is_mon_state_ctor : Ast.ident -> bool
(** Compile iexpr. *)
val compile_iexpr : Support.env -> Ast.iexpr -> Why3.Ptree.expr
(** Compile term. *)
val compile_term : Support.env -> Ast.iexpr -> Why3.Ptree.term
(** Compute term apply op. *)
val term_apply_op :
  Ast.op -> Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
(** Compile term instance. *)
val compile_term_instance :
  Support.env ->
  Ast.ident -> Ast.ident -> Ast.ident list -> Ast.iexpr -> Why3.Ptree.term
(** Compile hexpr instance. *)
val compile_hexpr_instance :
  ?in_post:bool ->
  Support.env ->
  Ast.ident ->
  Ast.ident ->
  Ast.ident list ->
  (Ast.hexpr * Support.pre_k_info) list ->
  Ast.hexpr -> Why3.Ptree.term
(** Compile fo term instance. *)
val compile_fo_term_instance :
  ?in_post:bool ->
  Support.env ->
  Ast.ident ->
  Ast.ident ->
  Ast.ident list ->
  (Ast.hexpr * Support.pre_k_info) list -> Ast.fo -> Why3.Ptree.term
(** Build a term from outputs. *)
val term_of_outputs :
  Support.env -> Ast.vdecl list -> Why3.Ptree.term option
(** Compile hexpr. *)
val compile_hexpr :
  ?old:bool ->
  ?prefer_link:bool ->
  ?in_post:bool -> Support.env -> Ast.hexpr -> Why3.Ptree.term
(** Compile fo term. *)
val compile_fo_term :
  ?prefer_link:bool -> Support.env -> Ast.fo -> Why3.Ptree.term
(** Compile ltl term shift. *)
val compile_ltl_term_shift :
  ?prefer_link:bool ->
  ?in_post:bool -> Support.env -> int -> Ast.fo_ltl -> Why3.Ptree.term
(** Compile fo term shift. *)
val compile_fo_term_shift :
  ?prefer_link:bool ->
  ?in_post:bool -> Support.env -> bool -> Ast.fo -> Why3.Ptree.term
(** {1 Relational Rewriting} *)

(** Compute rel hexpr. *)
val rel_hexpr : Support.env -> Ast.hexpr -> Ast.hexpr
(** Compute ltl relational. *)
val ltl_relational : Support.env -> Ast.fo_ltl -> Ast.fo_ltl
(** Compute rel fo. *)
val rel_fo : Support.env -> Ast.fo -> Ast.fo
(** {1 Spec Fragments} *)

type spec_frag = { pre : Why3.Ptree.term list; post : Why3.Ptree.term list; }
(** Compute empty frag. *)
val empty_frag : spec_frag
(** Compute ltl spec. *)
val ltl_spec : Support.env -> Ast.fo_ltl -> spec_frag
(** {1 Pre_k Helpers} *)

(** Compute pre k source expr. *)
val pre_k_source_expr : Support.env -> Ast.iexpr -> Why3.Ptree.expr
(** Compute pre k source term. *)
val pre_k_source_term : Support.env -> Ast.iexpr -> Why3.Ptree.term
