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

(** JSON codec helpers for IR formulas used in proof-kernel payloads.

    This module centralizes the explicit JSON converters required by derived
    proof-kernel records that embed [Core_syntax.historical Ir.summary_formula] values. *)

(** JSON encoder for formula metadata. *)
val formula_meta_to_yojson : Ir.formula_meta -> Yojson.Safe.t

(** JSON decoder for formula metadata. *)
val formula_meta_of_yojson : Yojson.Safe.t -> (Ir.formula_meta, string) result

(** JSON encoder for summary formulas. *)
val summary_formula_to_yojson : Core_syntax.historical Ir.summary_formula -> Yojson.Safe.t

(** JSON decoder for summary formulas. *)
val summary_formula_of_yojson : Yojson.Safe.t -> (Core_syntax.historical Ir.summary_formula, string) result

(** JSON encoder for lists of summary formulas. *)
val summary_formula_list_to_yojson : Core_syntax.historical Ir.summary_formula list -> Yojson.Safe.t

(** JSON decoder for lists of summary formulas. *)
val summary_formula_list_of_yojson : Yojson.Safe.t -> (Core_syntax.historical Ir.summary_formula list, string) result

(** JSON encoder for semantic generated-obligation families. *)
val clause_family_to_yojson :
  Obligation_family_projection.clause_family -> Yojson.Safe.t

(** JSON decoder for semantic generated-obligation families. *)
val clause_family_of_yojson :
  Yojson.Safe.t -> (Obligation_family_projection.clause_family, string) result

(** JSON encoder for kernel-clause time tags. *)
val time_tag_to_yojson : Kernel_clause_projection.time_tag -> Yojson.Safe.t

(** JSON decoder for kernel-clause time tags. *)
val time_tag_of_yojson :
  Yojson.Safe.t -> (Kernel_clause_projection.time_tag, string) result

(** JSON encoder for classified kernel clauses. *)
val classified_clause_to_yojson :
  Kernel_clause_projection.classified_clause -> Yojson.Safe.t

(** JSON decoder for classified kernel clauses. *)
val classified_clause_of_yojson :
  Yojson.Safe.t -> (Kernel_clause_projection.classified_clause, string) result

(** JSON encoder for kernel-clause contexts. *)
val clause_context_to_yojson :
  Kernel_clause_projection.clause_context -> Yojson.Safe.t

(** JSON decoder for kernel-clause contexts. *)
val clause_context_of_yojson :
  Yojson.Safe.t -> (Kernel_clause_projection.clause_context, string) result
