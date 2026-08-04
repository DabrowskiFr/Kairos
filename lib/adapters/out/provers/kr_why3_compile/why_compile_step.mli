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

(** Compilation of imperative transition bodies.

    Translates Kairos method/statement sequences and already-selected transitions into
    WhyML expressions. Product-step helper generation owns the proof structure;
    this module only emits the imperative code executed by a transition. *)

(** [compile_transition_body env t] compiles the body of transition [t] into a
    WhyML expression. *)
val compile_transition_body :
  Why_compile_expr.env -> Kr_verification_ir.transition -> Why3.Ptree.expr

val compile_seq :
  Why_compile_expr.env -> Kr_domain_core_syntax.stmt list -> Why3.Ptree.expr
