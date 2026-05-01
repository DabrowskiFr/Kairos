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
open Why_compile

let emit_program_ast (ast : program_ast) : string =
  let mlw = ast.mlw in
  let module_info = ast.module_info in
  let buf = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buf in
  Mlw_printer.pp_mlw_file fmt mlw;
  Format.pp_print_flush fmt ();
  let out = Buffer.contents buf in
  (* [term_old] uses [Tat(t, "old")] so [Mlw_printer] emits [old t] directly;
     no post-processing needed for [old].

     [Ptree.Eif] requires three expressions; there is no way to suppress the
     else branch at the AST level when it is the unit value.  [Mlw_printer]
     always emits the explicit [else ()] even though WhyML allows omitting it.
     The pass below removes those redundant clauses at the text level. *)
  let remove_else_unit s =
    let len = String.length s in
    let b = Buffer.create len in
    let is_word_char = function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true | _ -> false in
    let rec skip_ws i =
      if i < len then match s.[i] with ' ' | '\t' | '\n' | '\r' -> skip_ws (i + 1) | _ -> i else i
    in
    let rec loop i =
      if i >= len then ()
      else if i + 4 <= len && String.sub s i 4 = "else" then
        let prev_ok = if i = 0 then true else not (is_word_char s.[i - 1]) in
        let j = i + 4 in
        let next_ok = if j >= len then true else not (is_word_char s.[j]) in
        if prev_ok && next_ok then
          let k = skip_ws j in
          if k + 1 < len && s.[k] = '(' then
            let k' = skip_ws (k + 1) in
            if k' < len && s.[k'] = ')' then
              let k'' = k' + 1 in
              loop k''
            else (
              Buffer.add_string b "else";
              loop j)
          else (
            Buffer.add_string b "else";
            loop j)
        else (
          Buffer.add_char b s.[i];
          loop (i + 1))
      else (
        Buffer.add_char b s.[i];
        loop (i + 1))
    in
    loop 0;
    Buffer.contents b
  in
  let out = remove_else_unit out in
  let insert_spec_group_comments s =
    let contains_sub s sub =
      let len_s = String.length s in
      let len_sub = String.length sub in
      let rec loop i =
        if i + len_sub > len_s then false
        else if String.sub s i len_sub = sub then true
        else loop (i + 1)
      in
      if len_sub = 0 then true else loop 0
    in
    let starts_with_module line = String.length line >= 7 && String.sub line 0 7 = "module " in
    let lines = Array.of_list (String.split_on_char '\n' s) in
    let line_count = Array.length lines in
    let module_starts =
      let acc = ref [] in
      for i = 0 to line_count - 1 do
        if starts_with_module lines.(i) then acc := i :: !acc
      done;
      List.rev !acc
    in
    let module_ranges =
      match module_starts with
      | [] -> []
      | _ ->
          let rec build acc = function
            | [ start ] -> List.rev ((start, line_count) :: acc)
            | start :: (next :: _ as rest) -> build ((start, next) :: acc) rest
            | [] -> List.rev acc
          in
          build [] module_starts
    in
    let comment_for label indent = indent ^ "(* " ^ label ^ " *)" in
    let out = Buffer.create (String.length s) in
    let current = ref 0 in
    let range_idx = ref 0 in
    let ranges = Array.of_list module_ranges in
    let active_groups = ref None in
    let req_idx = ref 0 in
    let ens_idx = ref 0 in
    while !current < line_count do
      while
        !range_idx < Array.length ranges
        && !current
           >=
           let _, e = ranges.(!range_idx) in
           e
      do
        incr range_idx
      done;
      let in_module =
        if !range_idx < Array.length ranges then
          let s_idx, e_idx = ranges.(!range_idx) in
          !current >= s_idx && !current < e_idx
        else false
      in
      if in_module && !current = fst ranges.(!range_idx) then (
        let line = lines.(!current) in
        let name =
          let parts = String.split_on_char ' ' line in
          match parts with _ :: mod_name :: _ -> mod_name | _ -> ""
        in
        let groups =
          List.assoc_opt name module_info
          |> Option.value ~default:{ pre_labels = []; post_labels = [] }
        in
        active_groups := Some (groups.pre_labels, groups.post_labels);
        req_idx := 0;
        ens_idx := 0);
      let line = lines.(!current) in
      let trimmed = String.trim line in
      let indent =
        let len = String.length line in
        let rec loop i =
          if i >= len then "" else if line.[i] = ' ' then loop (i + 1) else String.sub line 0 i
        in
        loop 0
      in
      begin match !active_groups with
      | Some (pre_labels, post_labels) ->
          if String.length trimmed >= 9 && String.sub trimmed 0 9 = "requires " then (
            let label =
              if !req_idx < List.length pre_labels then List.nth pre_labels !req_idx else "Autres"
            in
            let prev_label =
              if !req_idx = 0 then None
              else if !req_idx - 1 < List.length pre_labels then
                Some (List.nth pre_labels (!req_idx - 1))
              else None
            in
            if prev_label <> Some label then Buffer.add_string out (comment_for label indent ^ "\n");
            incr req_idx)
          else if String.length trimmed >= 8 && String.sub trimmed 0 8 = "ensures " then
            let label =
              if !ens_idx < List.length post_labels then List.nth post_labels !ens_idx else "Autres"
            in
            let is_g_label =
              String.length label > 1
              && label.[0] = 'G'
              &&
                try
                  ignore (int_of_string (String.sub label 1 (String.length label - 1)));
                  true
                with _ -> false
            in
            let has_old = contains_sub trimmed "old(" in
            let prev_label =
              if !ens_idx = 0 then None
              else if !ens_idx - 1 < List.length post_labels then
                Some (List.nth post_labels (!ens_idx - 1))
              else None
            in
            if (not is_g_label) || has_old then (
              if prev_label <> Some label then
                Buffer.add_string out (comment_for label indent ^ "\n");
              incr ens_idx)
      | None -> ()
      end;
      Buffer.add_string out line;
      if !current < line_count - 1 then Buffer.add_char out '\n';
      incr current
    done;
    Buffer.contents out
  in
  let insert_user_code_comment s =
    let contains_sub s sub =
      let len_s = String.length s in
      let len_sub = String.length sub in
      let rec loop i =
        if i + len_sub > len_s then false
        else if String.sub s i len_sub = sub then true
        else loop (i + 1)
      in
      if len_sub = 0 then true else loop 0
    in
    let lines = Array.of_list (String.split_on_char '\n' s) in
    let line_count = Array.length lines in
    let out = Buffer.create (String.length s + 64) in
    let injected = ref false in
    for i = 0 to line_count - 1 do
      let line = lines.(i) in
      if (not !injected) && contains_sub line "match vars.st with" then (
        Buffer.add_string out "  (* user code *)\n";
        injected := true);
      Buffer.add_string out line;
      if i < line_count - 1 then Buffer.add_char out '\n'
    done;
    Buffer.contents out
  in
  let out = insert_spec_group_comments out in
  let out = insert_user_code_comment out in
  let out = out in
  let annotate_vars_fields s =
    let has_prefix name p =
      String.length name >= String.length p && String.sub name 0 (String.length p) = p
    in
    let field_comment name =
      if has_prefix name "__pre_k" then Some "k-step history"
      else if name = "st" then None
      else Some "user local"
    in
    let trim_left s =
      let len = String.length s in
      let rec loop i =
        if i >= len then ""
        else if s.[i] = ' ' || s.[i] = '\t' then loop (i + 1)
        else String.sub s i (len - i)
      in
      loop 0
    in
    let lines = Array.of_list (String.split_on_char '\n' s) in
    let line_count = Array.length lines in
    let out = Buffer.create (String.length s + 64) in
    let in_vars = ref false in
    for i = 0 to line_count - 1 do
      let line = lines.(i) in
      let trimmed = trim_left line in
      if String.length trimmed >= 12 && String.sub trimmed 0 12 = "type vars =" then in_vars := true
      else if !in_vars && trimmed = "}" then in_vars := false;
      let line =
        if !in_vars then
          match String.split_on_char ':' trimmed with
          | name :: _rest ->
              let name = String.trim name in
              let name =
                if String.length name >= 8 && String.sub name 0 8 = "mutable " then
                  String.sub name 8 (String.length name - 8)
                else name
              in
              begin match field_comment name with
              | None -> line
              | Some msg -> line ^ " (* " ^ msg ^ " *)"
              end
          | _ -> line
        else line
      in
      Buffer.add_string out line;
      if i < line_count - 1 then Buffer.add_char out '\n'
    done;
    Buffer.contents out
  in
  annotate_vars_fields out

let emit_program_ast_with_spans (ast : program_ast) : string * (int * (int * int)) list =
  let out = emit_program_ast ast in
  (out, [])
