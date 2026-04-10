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

(** Pipeline entry points for the Why3 backend.

    Exposes the two passes of the Why3 backend in the form expected by the
    Kairos pipeline. Each pass receives a [build_ast_with_info] constructor
    and returns a typed {!Pipeline_types} result. *)

(** [why_pass nodes] compiles a list of IR nodes to WhyML text. *)
val why_pass : Ir.node_ir list -> string

(** [obligations_pass ~prover nodes] compiles IR nodes and generates
    verification obligations as WhyML and SMT-LIB2 text. *)
val obligations_pass : prover:string -> Ir.node_ir list -> Pipeline_types.obligations_outputs
