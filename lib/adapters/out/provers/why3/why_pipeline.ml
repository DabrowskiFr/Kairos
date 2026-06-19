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

let obligations_pass
    ?(share_why3_facts = true)
    ?(simplify_why3_formulas = true)
    ?(slice_why3_transition_bodies = true)
    ?(simplify_why3_runtime_actions = true)
    ?(deduplicate_why3_terms = true)
    (nodes : Ir.node_ir list) : obligations_outputs =
  let why_ast =
    Why_compile.compile_program_ast_from_ir_nodes ~share_why3_facts
      ~simplify_why3_formulas ~slice_why3_transition_bodies
      ~simplify_why3_runtime_actions ~deduplicate_why3_terms nodes
  in
  let why_text = Why_text_render.emit_program_ast why_ast in
  let _cfg, _main, env, _datadir_opt = Why_task_support.setup_env () in
  let tasks =
    Why_task_support.normalize_tasks_of_text ~env ~filename:"<kairos-generated>"
      ~text:why_text
  in
  let vc_text =
    join_blocks ~sep:"\n(* ---- goal ---- *)\n"
      (Why_task_dump_render.dump_why3_tasks_with_attrs_of_tasks tasks)
  in
  let smt_text =
    join_blocks ~sep:"\n; ---- goal ----\n"
      (Why_task_dump_render.dump_smt2_tasks_of_tasks tasks)
  in
  { vc_text; smt_text }
