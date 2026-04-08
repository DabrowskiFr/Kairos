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

open Why3

let compile_seq = Why_core.compile_seq
let compile_transitions = Why_core.compile_transitions
let compile_runtime_view = Why_core.compile_runtime_view

type spec_groups = Why_emit_types.spec_groups
type comment_specs = Why_emit_types.comment_specs
type program_ast = Why_emit_types.program_ast

let compile_program_ast_from_ir_nodes = Why_emit_compile.compile_program_ast_from_ir_nodes
let emit_program_ast = Why_emit_render.emit_program_ast
let emit_program_ast_with_spans = Why_emit_render.emit_program_ast_with_spans
