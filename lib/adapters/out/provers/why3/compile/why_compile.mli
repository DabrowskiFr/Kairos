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

(** Public facade of the Why3 proof-plan translator.

    This module exposes only the entry point needed by the proof pipeline.
    Node-local WhyML construction details remain private and may not alter the
    completed
    {!Kairos_verification_obligations.Verification_proof_ir.t}. *)

type compiled_obligation = {
  generated_symbol : string;
  source : string;
  node_name : string;
  transition : string;
  obligation_kind : string;
  obligation_family : string;
  obligation_category : string option;
}

type compilation = {
  ast : Why3.Ptree.mlw_file;
  manifest : compiled_obligation list;
}

val compile_program_ast :
  proof_plans:
    Kairos_verification_obligations.Verification_proof_ir.t list ->
  unit ->
  compilation
