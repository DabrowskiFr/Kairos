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

(** Compiles Kairos expressions and formulas into Why3 terms. *)

(* {1 Term Compilation} *)

(* Compile an immediate expression to Why3 expr. *)
val compile_iexpr : Why_term_support.env -> Ast.iexpr -> Why3.Ptree.expr

(* Compile an immediate expression to Why3 term. *)
val compile_term : Why_term_support.env -> Ast.iexpr -> Why3.Ptree.term

(* Compile a term for an instance (qualified by node/instance names). *)
val compile_term_instance :
  Why_term_support.env -> Ast.ident -> Ast.ident -> Ast.ident list -> Ast.iexpr -> Why3.Ptree.term

(* Compile a historical expression for an instance using the kernel-guided
   temporal contract instead of a raw pre_k materialization map. *)
val compile_hexpr_instance_contract :
  ?in_post:bool ->
  Why_term_support.env ->
  Ast.ident ->
  Ast.ident ->
  Ast.ident list ->
  Kernel_guided_contract.exported_summary_contract ->
  Ast.hexpr ->
  Why3.Ptree.term

(* Compile a FO formula for an instance using the kernel-guided temporal
   contract instead of a raw pre_k materialization map. *)
val compile_fo_term_instance_contract :
  ?in_post:bool ->
  Why_term_support.env ->
  Ast.ident ->
  Ast.ident ->
  Ast.ident list ->
  Kernel_guided_contract.exported_summary_contract ->
  Ast.fo_atom ->
  Why3.Ptree.term

val compile_ltl_term_instance_contract :
  ?in_post:bool ->
  Why_term_support.env ->
  Ast.ident ->
  Ast.ident ->
  Ast.ident list ->
  Kernel_guided_contract.exported_summary_contract ->
  Ast.ltl ->
  Why3.Ptree.term

(* Build a tuple term from output variables (if any). *)
val term_of_outputs : Why_term_support.env -> Ast.vdecl list -> Why3.Ptree.term option

(* Compile a historical expression to a Why3 term. *)
val compile_hexpr :
  ?old:bool -> ?prefer_link:bool -> ?in_post:bool -> Why_term_support.env -> Ast.hexpr -> Why3.Ptree.term

(* Compile a FO formula to a Why3 term. *)
val compile_fo_term : ?prefer_link:bool -> Why_term_support.env -> Ast.fo_atom -> Why3.Ptree.term

(* Compile a local IR formula directly, without temporal reindexing. Rejects
   residual temporal operators because the middle-end must have eliminated or
   localized them before Why compilation. *)
val compile_local_ltl_term :
  ?prefer_link:bool -> ?in_post:bool -> Why_term_support.env -> Ast.ltl -> Why3.Ptree.term

(* Compile a FO formula shifted by k (temporal unrolling). *)
val compile_fo_term_shift :
  ?prefer_link:bool -> ?in_post:bool -> Why_term_support.env -> bool -> Ast.fo_atom -> Why3.Ptree.term
(* {1 Pre_k Helpers} *)

(* Build source expr for a pre‑k variable. *)
val pre_k_source_expr : Why_term_support.env -> Ast.iexpr -> Why3.Ptree.expr

(* Build source term for a pre‑k variable. *)
val pre_k_source_term : Why_term_support.env -> Ast.iexpr -> Why3.Ptree.term
