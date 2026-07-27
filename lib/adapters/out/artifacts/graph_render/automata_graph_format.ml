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

open Pretty

let render_automaton_lines ~prefix labels =
  labels |> List.mapi (fun i lbl -> Printf.sprintf "%s%d = %s" prefix i lbl)

let strip_braces (s : string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let rec loop i =
    if i >= len then ()
    else (
      let c = s.[i] in
      if c <> '{' && c <> '}' then Buffer.add_char b c;
      loop (i + 1))
  in
  loop 0;
  Buffer.contents b

let rewrite_history_vars (s : string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let is_digit c = c >= '0' && c <= '9' in
  let is_ident_char c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '_'
  in
  let rec loop i =
    if i >= len then ()
    else if i + 7 <= len && String.sub s i 7 = "__pre_k" then
      let j = i + 7 in
      let rec read_digits k =
        if k < len && is_digit s.[k] then read_digits (k + 1) else k
      in
      let k = read_digits j in
      if k > j && k < len && s.[k] = '_' then
        let var_start = k + 1 in
        let rec read_ident m =
          if m < len && is_ident_char s.[m] then read_ident (m + 1) else m
        in
        let var_end = read_ident var_start in
        if var_end > var_start then (
          let k_str = String.sub s j (k - j) in
          let v = String.sub s var_start (var_end - var_start) in
          if k_str = "1" then Buffer.add_string b ("pre(" ^ v ^ ")")
          else Buffer.add_string b ("pre_k(" ^ v ^ ", " ^ k_str ^ ")");
          loop var_end)
        else (
          Buffer.add_char b s.[i];
          loop (i + 1))
      else (
        Buffer.add_char b s.[i];
        loop (i + 1))
    else (
      Buffer.add_char b s.[i];
      loop (i + 1))
  in
  loop 0;
  Buffer.contents b

let pretty_product_formula (f : Core_syntax.historical Core_syntax.hexpr) : string =
  f |> string_of_fo |> strip_braces |> rewrite_history_vars

let replace_all ~pattern ~by s =
  let plen = String.length pattern in
  if plen = 0 then s
  else
    let buf = Buffer.create (String.length s) in
    let rec loop i =
      if i >= String.length s then ()
      else if i + plen <= String.length s && String.sub s i plen = pattern then (
        Buffer.add_string buf by;
        loop (i + plen))
      else (
        Buffer.add_char buf s.[i];
        loop (i + 1))
    in
    loop 0;
    Buffer.contents buf

let replace_word ~word ~by s =
  let wlen = String.length word in
  let slen = String.length s in
  let is_ident_char c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '_'
  in
  let buf = Buffer.create slen in
  let rec loop i =
    if i >= slen then ()
    else if i + wlen <= slen && String.sub s i wlen = word then
      let before_ok = i = 0 || not (is_ident_char s.[i - 1]) in
      let after_ok = i + wlen >= slen || not (is_ident_char s.[i + wlen]) in
      if before_ok && after_ok then (
        Buffer.add_string buf by;
        loop (i + wlen))
      else (
        Buffer.add_char buf s.[i];
        loop (i + 1))
    else (
      Buffer.add_char buf s.[i];
      loop (i + 1))
  in
  loop 0;
  Buffer.contents buf

let mathify_formula (s : string) : string =
  s
  |> replace_all ~pattern:"<>" ~by:"≠"
  |> replace_all ~pattern:" -> " ~by:" → "
  |> replace_all ~pattern:" and " ~by:" ∧ "
  |> replace_all ~pattern:" or " ~by:" ∨ "
  |> replace_all ~pattern:"not " ~by:"¬"
  |> replace_word ~word:"true" ~by:"⊤"
  |> replace_word ~word:"false" ~by:"⊥"

let pretty_plain_dot_formula (f : Core_syntax.historical Core_syntax.hexpr) : string =
  f |> pretty_product_formula |> mathify_formula

let subscript_digits (n : int) : string =
  let map = function
    | '0' -> "₀"
    | '1' -> "₁"
    | '2' -> "₂"
    | '3' -> "₃"
    | '4' -> "₄"
    | '5' -> "₅"
    | '6' -> "₆"
    | '7' -> "₇"
    | '8' -> "₈"
    | '9' -> "₉"
    | c -> String.make 1 c
  in
  string_of_int n |> String.to_seq |> List.of_seq |> List.map map
  |> String.concat ""

let pretty_aut_state ~prefix ~idx ~bad_idx =
  if bad_idx >= 0 && idx = bad_idx then Printf.sprintf "%s_bad" prefix
  else prefix ^ subscript_digits idx

let tau_alias (i : int) : string = "τ" ^ subscript_digits i
let phi_alias (i : int) : string = "φ" ^ subscript_digits i

let split_all_on sep s =
  let sep_len = String.length sep in
  let rec loop acc start =
    if start > String.length s then List.rev acc
    else
      let rec find i =
        if i + sep_len > String.length s then None
        else if String.sub s i sep_len = sep then Some i
        else find (i + 1)
      in
      match find start with
      | None -> List.rev (String.sub s start (String.length s - start) :: acc)
      | Some i ->
          let piece = String.sub s start (i - start) in
          loop (piece :: acc) (i + sep_len)
  in
  loop [] 0

let wrap_formula_lines ?(max_width = 72) (s : string) : string list =
  let s = String.trim s in
  let join_wrapped sep pieces =
    let rec loop acc current = function
      | [] -> List.rev (String.trim current :: acc)
      | piece :: rest ->
          let piece = String.trim piece in
          let candidate = if current = "" then piece else current ^ sep ^ piece in
          if current <> "" && String.length candidate > max_width then
            loop (String.trim current :: acc) piece rest
          else loop acc candidate rest
    in
    loop [] "" pieces
  in
  if s = "" || String.length s <= max_width then [ s ]
  else
    let by_or = split_all_on " ∨ " s in
    if List.length by_or > 1 then join_wrapped " ∨ " by_or
    else
      let by_and = split_all_on " ∧ " s in
      if List.length by_and > 1 then join_wrapped " ∧ " by_and else [ s ]

let compact_display_string (s : string) : string =
  s |> strip_braces |> rewrite_history_vars
