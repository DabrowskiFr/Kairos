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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Clause normalization boundary for proof-kernel export.

    The pass removes trivially impossible/trivial generated clauses, then
    lowers remaining timed facts into the relational proof-export form used by
    proof-step summaries and diagnostics. *)

(** Drop generated clauses with false hypotheses or no effective conclusion,
    and remove trivially true facts. *)
val lower_generated_clause :
  Proof_kernel_types.generated_clause_ir ->
  Proof_kernel_types.generated_clause_ir option

(** Relationalize a generated clause and split disjunctive hypotheses into
    independent lowered clauses. *)
val relationalize_generated_clause :
  Proof_kernel_types.generated_clause_ir ->
  Proof_kernel_types.relational_generated_clause_ir list
