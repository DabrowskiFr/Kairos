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

(** Why/VC/SMT obligations export pass extracted from the v2 pipeline implementation. *)

type obligations_outputs = {
  vc_text : string;
  smt_text : string;
}

let join_blocks ~sep blocks =
  let b = Buffer.create 4096 in
  List.iteri
    (fun i s ->
      if i > 0 then Buffer.add_string b sep;
      Buffer.add_string b s)
    blocks;
  Buffer.contents b

let obligations_pass (nodes : Ir.node_ir list) : obligations_outputs =
  let ptree = (Why_compile.compile_program_ast_from_ir_nodes nodes).Why_compile.mlw in
  let vc_text =
    join_blocks ~sep:"\n(* ---- goal ---- *)\n"
      (Why_task_dump_render.dump_why3_tasks_with_attrs_of_ptree ~ptree)
  in
  let smt_text =
    join_blocks ~sep:"\n; ---- goal ----\n"
      (Why_task_dump_render.dump_smt2_tasks_of_ptree ~ptree)
  in
  { vc_text; smt_text }
