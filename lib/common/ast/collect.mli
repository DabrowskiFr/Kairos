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

(* {1 Expression Collection} Collectors traverse expressions/formulas and accumulate referenced
   historical expressions ([hexpr]) or call sites. These helpers are used by monitor generation and
   OBC+ instrumentation. *)

(* Collect hexprs referenced by a hexpr, preserving uniqueness. *)
val collect_hexpr : Ast.hexpr -> Ast.hexpr list -> Ast.hexpr list

(* Collect hexprs referenced by an LTL formula. *)
val collect_ltl : Ast.fo_ltl -> Ast.hexpr list -> Ast.hexpr list

(* Collect hexprs referenced by a FO formula. *)
val collect_fo : Ast.fo -> Ast.hexpr list -> Ast.hexpr list
(* {1 Fold And Pre_k Extraction} *)

(* Extract all pre‑k expressions from a set of specs/invariants. *)
val collect_pre_k_from_specs :
  fo:Ast.fo list ->
  ltl:Ast.fo_ltl list ->
  invariants_user:Ast.invariant_user list ->
  invariants_state_rel:Ast.invariant_state_rel list ->
  Ast.hexpr list

(* Build per‑node pre‑k metadata (name, type, init). *)
val build_pre_k_infos : Ast.node -> (Ast.hexpr * Support.pre_k_info) list
(* {1 Call-Site Collection} *)

(* Collect call sites (instance + args) from a statement. *)
val collect_calls_stmt :
  (Ast.ident * Ast.iexpr list) list -> Ast.stmt -> (Ast.ident * Ast.iexpr list) list

(* Collect call sites from a list of transitions. *)
val collect_calls_trans : Ast.transition list -> (Ast.ident * Ast.iexpr list) list

(* Collect call sites including outputs from a statement. *)
val collect_calls_stmt_full :
  (Ast.ident * Ast.iexpr list * Ast.ident list) list ->
  Ast.stmt ->
  (Ast.ident * Ast.iexpr list * Ast.ident list) list

(* Collect call sites including outputs from transitions. *)
val collect_calls_trans_full :
  Ast.transition list -> (Ast.ident * Ast.iexpr list * Ast.ident list) list
(* {1 Spec Heuristics} *)

(* Detect a delay‑spec pattern and return (out, in) if present. *)
val extract_delay_spec : Ast.fo_ltl list -> (Ast.ident * Ast.ident) option
