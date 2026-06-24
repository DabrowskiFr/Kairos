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

(** Formatting helpers for timing flow metadata. *)

val fmt_s : float -> string

val bool_s : bool -> string

val sanitize_csv_value : string -> string

val solver_sum_s : Pipeline_types.goal_info list -> float

val goal_status_is_pending : Pipeline_types.goal_info -> bool

val why3_worker_timing_fields :
  Application_ports.why3_worker_counters -> (string * string) list

val ir_pass_size_fields :
  Application_ports.ir_pass_counters -> (string * string) list

val ir_fact_family_fields :
  Application_ports.ir_fact_family_counters -> (string * string) list

val product_group_fields :
  Application_ports.why3_product_group_counters list -> (string * string) list

val product_individual_reason_fields :
  Application_ports.why3_product_individual_reason_counters list ->
  (string * string) list
