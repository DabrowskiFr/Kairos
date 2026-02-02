(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

module A = Ast

let compile_program_with_transform ?(prefix_fields=true)
  (transform:A.node -> A.node) (p:A.program) : string =
  let p' = List.map transform p in
  Emit.compile_program ~prefix_fields p'

let compile_program ?(prefix_fields=true) (p:A.program) : string =
  compile_program_with_transform ~prefix_fields Monitor_instrument.transform_node p

let compile_program_monitor ?(prefix_fields=true) (p:A.program) : string =
  let is_instrumented (n:A.node) =
    List.exists (fun v -> v.A.vname = "__mon_state") n.A.locals
  in
  let p' =
    List.map
      (fun n ->
         if is_instrumented n then n
         else
           n
           |> Monitor_instrument.transform_node_monitor
           |> Ghost_instrument.transform_node_ghost)
      p
  in
  let comment_map =
    List.map
      (fun (n:A.node) -> (n.nname, (n.assumes, n.guarantees, n.trans, [])))
      p'
  in
  Emit_why_contracts.set_pure_translation true;
  let out = Emit.compile_program ~prefix_fields ~comment_map p' in
  Emit_why_contracts.set_pure_translation false;
  out
