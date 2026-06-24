(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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
open Ptree

let normalize_infix (s : string) : string =
  let prefix = "infix " in
  if
    String.length s > String.length prefix
    && String.sub s 0 (String.length prefix) = prefix
  then String.sub s (String.length prefix) (String.length s - String.length prefix)
  else s

let string_of_qid (q : Ptree.qualid) : string =
  let rec aux = function
    | Ptree.Qident id -> id.id_str
    | Ptree.Qdot (q, id) -> aux q ^ "." ^ id.id_str
  in
  aux q

let string_of_const (c : Why3.Constant.constant) : string =
  Format.asprintf "%a" Why3.Constant.print_def c

let rec string_of_term (t : Ptree.term) : string =
  let aux = string_of_term in
  match t.term_desc with
  | Tconst c -> string_of_const c
  | Ttrue -> "true"
  | Tfalse -> "false"
  | Tident q -> string_of_qid q
  | Tinnfix (a, op, b) ->
      let op_str = normalize_infix op.id_str in
      "(" ^ aux a ^ " " ^ op_str ^ " " ^ aux b ^ ")"
  | Tbinnop (a, d, b) ->
      let op =
        match d with
        | Dterm.DTand -> "/\\"
        | Dterm.DTor -> "\\/"
        | Dterm.DTimplies -> "->"
        | _ -> "?"
      in
      "(" ^ aux a ^ " " ^ op ^ " " ^ aux b ^ ")"
  | Tnot a -> "not " ^ aux a
  | Tidapp (q, args) ->
      string_of_qid q ^ "(" ^ String.concat ", " (List.map aux args) ^ ")"
  | Tat (t', id) ->
      if id.id_str = "old" then "old(" ^ aux t' ^ ")"
      else aux t' ^ "@" ^ id.id_str
  | Tapply (f, a) -> begin
      match f.term_desc with
      | Tident q when string_of_qid q = "old" -> "old(" ^ aux a ^ ")"
      | _ -> aux f ^ "(" ^ aux a ^ ")"
    end
  | _ -> "?"

let uniq_terms (terms : Ptree.term list) : Ptree.term list =
  let rec aux seen acc = function
    | [] -> List.rev acc
    | t :: ts ->
        let key = string_of_term t in
        if List.mem key seen then aux seen acc ts
        else aux (key :: seen) (t :: acc) ts
  in
  aux [] [] terms
