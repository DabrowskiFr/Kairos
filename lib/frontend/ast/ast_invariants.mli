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

(** Invariant-oriented traversals and helper operations over Kairos AST nodes
    and formulas. *)

type issue = string

(* {1 Validation helpers} Lightweight checks for structural invariants. These are intended for
   debugging/CLI validation rather than full semantic verification. *)

(* Check structural sanity of the core AST (nodes, transitions, states). *)
val check_program_basic : Ast.program -> issue list

(* Check invariants after contract enrichment (coherency/compatibility). *)
val check_program_contracts : Ast.program -> issue list

(* Check invariants after monitor injection. *)
val check_program_monitor : Ast.program -> issue list

(* No-op check (monitor metadata is no longer embedded in the AST). *)
val check_program_obc : Ast.program -> issue list
(* No-op check (OBC+ metadata is no longer embedded in the AST). *)
