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

(** SMT-LIB text utilities for Why3 proof execution. *)

val answer_status : Why3.Call_provers.prover_answer -> string

val dump_path_of_prover_answer :
  dump_failed_smt:bool ->
  task_index:int ->
  prover_result:Why3.Call_provers.prover_result ->
  buffer:Buffer.t ->
  string option

val smt_fingerprint : string -> string
