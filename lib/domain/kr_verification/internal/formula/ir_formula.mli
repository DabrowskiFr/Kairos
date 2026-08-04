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

(** Helpers over [Kr_verification_ir.summary_formula]. *)
open Kr_domain_core_syntax
(** [make] service entrypoint. *)

val make :
  ?loc:Kr_domain_core_locations.loc ->
  ?family:string ->
  'phase Kr_domain_core_syntax.hexpr ->
  'phase Kr_verification_ir.summary_formula

(** [values] service entrypoint. *)

val values : 'phase Kr_verification_ir.summary_formula list -> 'phase Kr_domain_core_syntax.hexpr list

(** [temporal_bindings_of_layout] service entrypoint. *)

val temporal_bindings_of_layout :
  Kr_verification_ir.temporal_layout ->
  Kr_domain_core.Kr_domain_core_history.temporal_binding list

(** [temporal_bindings_of_node] service entrypoint. *)

val temporal_bindings_of_node :
  Kr_domain_core_syntax.historical Kr_verification_ir.node_ir ->
  Kr_domain_core.Kr_domain_core_history.temporal_binding list
