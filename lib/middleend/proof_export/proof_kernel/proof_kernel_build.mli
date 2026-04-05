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

val of_node_analysis :
  node_name:Ast.ident ->
  source_node:Ast.node ->
  node:Ir.node_ir ->
  analysis:Product_build.analysis ->
  Proof_kernel_types.node_ir

val export_node_summary :
  source_node:Ast.node ->
  node:Ir.node_ir ->
  normalized_ir:Proof_kernel_types.node_ir ->
  Proof_kernel_types.exported_node_summary_ir
