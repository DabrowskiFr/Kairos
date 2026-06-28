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

(** Current-input freedom for end-of-instant FO facts.

    A formula is current-input-free when no current input appears as [HVar].
    Historical input occurrences are represented by [HPreK] before temporal
    lowering, and by generated temporal slots after lowering; both are allowed.
*)

val input_names : Core_syntax.vdecl list -> Core_syntax.ident list
(** Stable list of input names extracted from declarations. *)

val current_inputs :
  input_names:Core_syntax.ident list -> Core_syntax.hexpr -> Core_syntax.ident list
(** Current input variables that occur as plain [HVar] nodes. *)

val no_current_input :
  input_names:Core_syntax.ident list -> Core_syntax.hexpr -> bool
(** [true] iff {!current_inputs} is empty. *)

val require_no_current_input :
  context:string ->
  input_names:Core_syntax.ident list ->
  Core_syntax.hexpr ->
  Core_syntax.hexpr
(** Return the formula unchanged when it is current-input-free; otherwise fail
    with a diagnostic containing [context]. *)
