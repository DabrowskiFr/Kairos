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

(** Final frontend translation from the elaborated Kairos AST to the model used
    by the verification engine.

    Surface constructs have already been eliminated at this point. This module
    converts the remaining syntax, preserves source locations, validates the
    result, and applies transition prioritization. *)

(** Translate and validate one elaborated node, using the surrounding type and
    pure-function declarations. *)
val node :
  type_decls:Core_syntax.enum_decl list ->
  function_decls:Core_syntax.pure_function_decl list ->
  Core.Ast.node ->
  Verification_model.node_model

(** Translate a complete elaborated program and attach the shared declarations
    to every resulting node model. *)
val program :
  ?type_decls:Core.Syntax.enum_decl list ->
  ?function_decls:Core.Syntax.pure_function_decl list ->
  Core.Ast.program ->
  Verification_model.program_model
