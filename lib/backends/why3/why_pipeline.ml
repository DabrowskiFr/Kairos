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

(** Why/VC/SMT export passes extracted from the v2 pipeline implementation. *)

let join_blocks ~sep blocks =
  let b = Buffer.create 4096 in
  List.iteri
    (fun i s ->
      if i > 0 then Buffer.add_string b sep;
      Buffer.add_string b s)
    blocks;
  Buffer.contents b

let compile_why_text (nodes : Ir.node_ir list) =
  let why_ast = Why_compile.compile_program_ast_from_ir_nodes nodes in
  Why_render.emit_program_ast why_ast

let why_pass (nodes : Ir.node_ir list) : string = compile_why_text nodes

let obligations_pass ~(prover : string) (nodes : Ir.node_ir list) :
    Pipeline_types.obligations_outputs =
  let ptree = (Why_compile.compile_program_ast_from_ir_nodes nodes).Why_compile.mlw in
  let vc_text =
    join_blocks ~sep:"\n(* ---- goal ---- *)\n"
      (Why_contract_prove.dump_why3_tasks_with_attrs_of_ptree ~ptree)
  in
  let smt_text =
    join_blocks ~sep:"\n; ---- goal ----\n"
      (Why_contract_prove.dump_smt2_tasks_of_ptree ~prover ~ptree)
  in
  { Pipeline_types.vc_text; smt_text }
