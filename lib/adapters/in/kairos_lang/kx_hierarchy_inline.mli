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

(** Weak hierarchical-node elaboration.

    This frontend-only pass consumes static [instance] declarations and
    [call] statements, then returns ordinary call-free verification models.
    Downstream verification and code-generation passes therefore keep working
    on the same single-node representation as before.

    Every instance shares its owner's clock: every transition of its owner
    must call it exactly once, and all transitions must use the same instance
    order. Calls are therefore total rather than conditionally clocked. *)

val flatten_program :
  instance_decls:
    (Core_syntax.ident * (Core_syntax.ident * Core_syntax.ident) list) list ->
  Verification_model.program_model ->
  Verification_model.program_model
