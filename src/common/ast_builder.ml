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

type issue = string

let issue fmt = Printf.sprintf fmt

let build_transition ~src ~dst ~guard ~requires ~ensures ~body =
  let t = Ast.mk_transition ~src ~dst ~guard ~requires ~ensures ~body in
  let t = Ast.ensure_transition_uid t in
  Ok (t, [])

let build_node
    ~nname
    ~inputs
    ~outputs
    ~assumes
    ~guarantees
    ~instances
    ~locals
    ~states
    ~init_state
    ~trans =
  let issues = ref [] in
  let uniq l = List.sort_uniq String.compare l in
  if List.length (uniq states) <> List.length states then
    issues := issue "node '%s' has duplicate states" nname :: !issues;
  if not (List.mem init_state states) then
    issues := issue "node '%s' init_state '%s' not in states" nname init_state :: !issues;
  let n =
    Ast.mk_node
      ~nname
      ~inputs
      ~outputs
      ~assumes
      ~guarantees
      ~instances
      ~locals
      ~states
      ~init_state
      ~trans
  in
  let n = Ast.ensure_node_uid n in
  Ok (n, List.rev !issues)
