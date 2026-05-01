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

(** Render Why3 AST to text for artifact export/UI display. *)

(** Render a Why program AST into final WhyML text.

    @param ast
      Structured Why AST built from IR.
    @return
      WhyML source text after rendering passes. *)
val emit_program_ast : Why_compile.program_ast -> string

(** Render WhyML text and return origin spans for labeled fragments.

    @param ast
      Structured Why AST built from IR.
    @return
      [(text, spans)] where [spans] maps stable identifiers (when available) to
      byte offsets in the rendered text. *)
val emit_program_ast_with_spans :
  Why_compile.program_ast -> string * (int * (int * int)) list
