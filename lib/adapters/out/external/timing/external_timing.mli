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

(** Process-local timing counters for external backends. *)

type snapshot = {
  spot_s : float;
  spot_calls : int;
  z3_s : float;
  z3_calls : int;
  product_s : float;
  canonical_s : float;
  why_gen_s : float;
  vc_smt_s : float;
  why3_prepare_s : float;
  why3_print_s : float;
  why3_spawn_s : float;
  why3_wait_s : float;
  why3_solver_s : float;
  why3_input_goal_count : int;
  why3_goal_count : int;
  why3_duplicate_goal_count : int;
  why3_fallback_count : int;
}

(** [reset] service entrypoint. *)

val reset : unit -> unit
(** Reset all counters to zero. *)

val snapshot : unit -> snapshot
(** Read current counter values. *)

val diff : before:snapshot -> after_:snapshot -> snapshot
(** Delta between two snapshots. *)

val record_spot : elapsed_s:float -> unit
(** Add one Spot call and its elapsed wall-clock time. *)

val record_z3 : elapsed_s:float -> unit
(** Add one Z3 simplify call and its elapsed wall-clock time. *)

val record_product : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent in product-state exploration. *)

val record_canonical : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent in canonical construction/enrichment. *)

val record_why_gen : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent generating Why3 text from IR. *)

val record_vc_smt : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent generating VCs and submitting to SMT. *)

val record_why3_prepare : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent preparing Why3 tasks. *)

val record_why3_print : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent printing prepared tasks to SMT-LIB. *)

val record_why3_spawn : elapsed_s:float -> unit
(** Add elapsed wall-clock time spent creating prover calls. *)

val record_why3_wait : elapsed_s:float -> solver_s:float -> unit
(** Add elapsed wall-clock and solver-reported time for one prover result. *)

val record_why3_input_goals : count:int -> unit
(** Add logical Why3 goals submitted to the proof loop before deduplication. *)

val record_why3_duplicate_goal : unit -> unit
(** Count one logical goal proved by reusing an identical SMT task result. *)

val record_why3_fallback : unit -> unit
(** Count one fallback prover attempt after a primary prover non-valid result. *)
