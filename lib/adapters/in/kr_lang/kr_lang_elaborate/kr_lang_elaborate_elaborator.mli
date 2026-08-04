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

(** Main surface-to-core elaboration pass.

    It validates surface-only constructs, expands indexed declarations and
    finite loops or quantifiers, orders observers, introduces required private
    ghosts, infers method effects, and lowers nodes to [Kr_lang_core.Kr_lang_core_ast]. Parsing and the
    later translation to [Kr_domain_core.Verification_model] are outside this module. *)

type source = {
  type_decls : Kr_lang_core.Kr_lang_core_syntax.enum_decl list;
      (** Elaborated global enum declarations. *)
  function_decls : Kr_lang_core.Kr_lang_core_syntax.pure_function_decl list;
      (** Elaborated global pure functions. *)
  nodes : Kr_lang_core.Kr_lang_core_ast.program; (** Elaborated program nodes. *)
}
(** Complete result of elaborating one parsed source file. *)

val elaborate_source : Kr_lang_surface.Kr_lang_surface_ast.source -> source
(** Validate and elaborate a complete surface source. Raises a classified
    frontend error when a surface construct cannot be lowered. *)
