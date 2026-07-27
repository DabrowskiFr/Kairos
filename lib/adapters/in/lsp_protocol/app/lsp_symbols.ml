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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

type semantic_symbols = Kairos_engine.Api.semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  variables : string list;
}

type document_symbol = { name : string; line : int; character : int }

let lines_of_text (text : string) : string array =
  text |> String.split_on_char '\n' |> Array.of_list

let is_ident_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' -> true
  | _ -> false

let identifier_at_line
    (line_s : string)
    (ch : int) :
    (string * int * int) option =
  let n = String.length line_s in
  if n = 0 then None
  else
    let i = max 0 (min (if ch >= n then n - 1 else ch) (n - 1)) in
    if not (is_ident_char line_s.[i]) then None
    else
      let rec left k =
        if k > 0 && is_ident_char line_s.[k - 1] then left (k - 1) else k
      in
      let rec right k =
        if k < n && is_ident_char line_s.[k] then right (k + 1) else k
      in
      let a = left i in
      let b = right i in
      if a >= b then None else Some (String.sub line_s a (b - a), a, b)

let identifier_at (text : string) (line : int) (character : int) :
    string option =
  let lines = lines_of_text text in
  if Array.length lines = 0 then None
  else
    let l = max 0 (min line (Array.length lines - 1)) in
    match identifier_at_line lines.(l) character with
    | Some (id, _, _) -> Some id
    | None -> None

let identifier_occurrences
    (text : string)
    (ident : string) :
    (int * int * int) list =
  let lines = lines_of_text text in
  let out = ref [] in
  Array.iteri
    (fun li line_s ->
      let n = String.length line_s in
      let m = String.length ident in
      if m > 0 && n >= m then
        for i = 0 to n - m do
          if String.sub line_s i m = ident then
            let left_ok = i = 0 || not (is_ident_char line_s.[i - 1]) in
            let right_ok =
              i + m = n || not (is_ident_char line_s.[i + m])
            in
            if left_ok && right_ok then out := (li, i, i + m) :: !out
        done)
    lines;
  List.rev !out

let semantic_symbols_for_text text =
  Kairos_engine.Api.semantic_symbols ~text

let symbol_kind (symbols : semantic_symbols) (ident : string) : string option =
  if List.mem ident symbols.nodes then Some "node"
  else if List.mem ident symbols.states then Some "state"
  else if List.mem ident symbols.variables then Some "variable"
  else if List.mem ident symbols.all then Some "symbol"
  else None

let first_definition_position
    ~(text : string)
    ~(ident : string)
    ~(symbols : semantic_symbols) :
    (int * int * int) option =
  let lines = lines_of_text text in
  let find_by_re re =
    let found = ref None in
    Array.iteri
      (fun li line_s ->
        if !found = None && Str.string_match re line_s 0 then
          match String.index_opt line_s ident.[0] with
          | Some i -> found := Some (li, i, i + String.length ident)
          | None -> ())
      lines;
    !found
  in
  if List.mem ident symbols.nodes then
    find_by_re (Str.regexp ("^[ \t]*node[ \t]+" ^ Str.quote ident ^ "\\b"))
  else if List.mem ident symbols.states then
    find_by_re
      (Str.regexp ("^[ \t]*states\\b.*\\b" ^ Str.quote ident ^ "\\b"))
  else if List.mem ident symbols.variables then
    find_by_re
      (Str.regexp ("^[ \t]*.*\\b" ^ Str.quote ident ^ "\\b[ \t]*[:,)]"))
  else None

let document_symbols_for_text (text : string) : document_symbol list =
  let sec = Lsp_outline.outline_sections_of_text text in
  List.map
    (fun (name, line) -> { name; line = max 0 (line - 1); character = 0 })
    sec.nodes
