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

(** {1 Expression Collection} *)

val collect_hexpr : Ast.hexpr -> Ast.hexpr list -> Ast.hexpr list
(** Collect hexprs referenced by a hexpr, preserving uniqueness. *)
val collect_ltl : Ast.ltl -> Ast.hexpr list -> Ast.hexpr list
(** Collect hexprs referenced by an LTL formula. *)
val collect_fo : Ast.fo -> Ast.hexpr list -> Ast.hexpr list
(** Collect hexprs referenced by a FO formula. *)
(** {1 Fold And Pre_k Extraction} *)

val fold_name : int -> string
(** Deterministic fold accumulator name for an index. *)
val classify_fold :
  Ast.hexpr ->
  [ `Scan of Ast.op * Ast.iexpr * Ast.iexpr | `Scan1 of Ast.op * Ast.iexpr ]
  option
(** Classify a fold hexpr into its operator and operands. *)
val collect_folds_from_specs :
  fo:Ast.fo list ->
  ltl:Ast.ltl list ->
  invariants_mon:Ast.invariant_mon list -> Support.fold_info list
(** Extract fold accumulators used by a set of specs. *)
val collect_pre_k_from_specs :
  fo:Ast.fo list ->
  ltl:Ast.ltl list -> invariants_mon:Ast.invariant_mon list -> Ast.hexpr list
(** Extract pre_k hexprs used by a set of specs. *)
val build_pre_k_infos :
  Ast.node -> (Ast.hexpr * Support.pre_k_info) list
(** Build pre_k metadata (names, types, init) for a node. *)
(** {1 Call-Site Collection} *)

val collect_calls_stmt :
  (Ast.ident * Ast.iexpr list) list ->
  Ast.stmt -> (Ast.ident * Ast.iexpr list) list
(** Collect call sites (instance + args) from a statement. *)
val collect_calls_trans :
  Ast.transition list -> (Ast.ident * Ast.iexpr list) list
(** Collect call sites from a list of transitions. *)
val collect_calls_stmt_full :
  (Ast.ident * Ast.iexpr list * Ast.ident list) list ->
  Ast.stmt -> (Ast.ident * Ast.iexpr list * Ast.ident list) list
(** Collect call sites including outputs from a statement. *)
val collect_calls_trans_full :
  Ast.transition list -> (Ast.ident * Ast.iexpr list * Ast.ident list) list
(** Collect call sites including outputs from transitions. *)
(** {1 Spec Heuristics} *)

val extract_delay_spec : Ast.ltl list -> (Ast.ident * Ast.ident) option
(** Detect a delay spec pattern and return (out, in) if present. *)
