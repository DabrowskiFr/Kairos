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

(* {1 Term Compilation} *)

(* Predicate for monitor state constructor identifiers. *)
val is_mon_state_ctor : Ast.ident -> bool

(* Compile an immediate expression to Why3 expr. *)
val compile_iexpr : Support.env -> Ast.iexpr -> Why3.Ptree.expr

(* Compile an immediate expression to Why3 term. *)
val compile_term : Support.env -> Ast.iexpr -> Why3.Ptree.term

(* Compile a term for an instance (qualified by node/instance names). *)
val compile_term_instance :
  Support.env -> Ast.ident -> Ast.ident -> Ast.ident list -> Ast.iexpr -> Why3.Ptree.term

(* Compile a historical expression for an instance using the kernel-guided
   temporal contract instead of a raw pre_k materialization map. *)
val compile_hexpr_instance_contract :
  ?in_post:bool ->
  Support.env ->
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
  Support.env ->
  Ast.ident ->
  Ast.ident ->
  Ast.ident list ->
  Kernel_guided_contract.exported_summary_contract ->
  Ast.fo ->
  Why3.Ptree.term

(* Build a tuple term from output variables (if any). *)
val term_of_outputs : Support.env -> Ast.vdecl list -> Why3.Ptree.term option

(* Compile a historical expression to a Why3 term. *)
val compile_hexpr :
  ?old:bool -> ?prefer_link:bool -> ?in_post:bool -> Support.env -> Ast.hexpr -> Why3.Ptree.term

(* Compile a FO formula to a Why3 term. *)
val compile_fo_term : ?prefer_link:bool -> Support.env -> Ast.fo -> Why3.Ptree.term

(* Compile an LTL formula shifted by k (temporal unrolling). *)
val compile_ltl_term_shift :
  ?prefer_link:bool -> ?in_post:bool -> Support.env -> int -> Ast.fo_ltl -> Why3.Ptree.term

(* Compile a FO formula shifted by k (temporal unrolling). *)
val compile_fo_term_shift :
  ?prefer_link:bool -> ?in_post:bool -> Support.env -> bool -> Ast.fo -> Why3.Ptree.term
(* {1 Relational Rewriting} *)

(* Replace variables by their relational form in a hexpr. *)
val rel_hexpr : Support.env -> Ast.hexpr -> Ast.hexpr

(* Replace variables by relational forms inside an LTL formula. *)
val ltl_relational : Support.env -> Ast.fo_ltl -> Ast.fo_ltl

(* Replace variables by relational forms inside a FO formula. *)
val rel_fo : Support.env -> Ast.fo -> Ast.fo
(* {1 Spec Fragments} *)

type spec_frag = { pre : Why3.Ptree.term list; post : Why3.Ptree.term list }

(* Empty spec fragment (no pre/post). *)
val empty_frag : spec_frag

(* Translate an LTL formula into pre/post fragments. *)
val ltl_spec : Support.env -> Ast.fo_ltl -> spec_frag
(* {1 Pre_k Helpers} *)

(* Build source expr for a pre‑k variable. *)
val pre_k_source_expr : Support.env -> Ast.iexpr -> Why3.Ptree.expr

(* Build source term for a pre‑k variable. *)
val pre_k_source_term : Support.env -> Ast.iexpr -> Why3.Ptree.term
