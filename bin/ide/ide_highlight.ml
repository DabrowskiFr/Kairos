open Ide_text_utils

let highlight_obc_buf ~(buf : GText.buffer) ~keyword_tag ~type_tag ~number_tag ~comment_tag
    ~state_tag text =
  let start_iter = buf#start_iter in
  let end_iter = buf#end_iter in
  buf#remove_all_tags ~start:start_iter ~stop:end_iter;
  let buf_text = buf#get_text ~start:start_iter ~stop:end_iter () in
  let text = buf_text in
  let map = build_utf8_map text in
  let apply_regex = apply_regex_to_buf buf text in
  let keywords =
    [
      "node";
      "returns";
      "guarantee";
      "assume";
      "contracts";
      "let";
      "locals";
      "states";
      "invariants";
      "invariant";
      "in";
      "init";
      "trans";
      "transitions";
      "when";
      "from";
      "to";
      "always";
      "next";
      "G";
      "X";
      "requires";
      "ensures";
      "if";
      "assumes";
      "guarantees";
      "then";
      "else";
      "end";
      "match";
      "with";
      "skip";
    ]
  in
  let types = [ "int"; "bool" ] in
  let number_re = Str.regexp "\\b[0-9]+\\b" in
  let comment_re = Str.regexp "(\\*.*\\*)" in
  ignore (apply_words buf text keyword_tag keywords);
  ignore (apply_words buf text type_tag types);
  ignore (apply_regex number_tag number_re);
  ignore (apply_regex comment_tag comment_re);
  let states_re = Str.regexp "\\bstates\\b" in
  let trans_re = Str.regexp "\\btrans\\(?:itions\\)?\\b" in
  let arrow_re =
    Str.regexp
      "\\b\\([A-Za-z_][A-Za-z0-9_]*\\)\\b[ \t\r\n]*->[ \t\r\n]*\\b\\([A-Za-z_][A-Za-z0-9_]*\\)\\b"
  in
  let src_group_re =
    Str.regexp "\\(?:^\\|[\n\r]\\)[ \t]*\\([A-Za-z_][A-Za-z0-9_]*\\)[ \t]*:"
  in
  let to_re = Str.regexp "\\bto\\s+\\([A-Za-z_][A-Za-z0-9_]*\\)\\b" in
  let apply_state_range s e =
    let s = char_offset map s in
    let e = char_offset map e in
    let it_s = buf#start_iter#forward_chars s in
    let it_e = buf#start_iter#forward_chars e in
    buf#apply_tag state_tag ~start:it_s ~stop:it_e
  in
  let highlight_states start_pos end_pos =
    let id_re = Str.regexp "\\b[A-Za-z_][A-Za-z0-9_]*\\b" in
    let rec loop pos =
      if pos >= end_pos then ()
      else
        try
          let _ = Str.search_forward id_re text pos in
          let s = Str.match_beginning () in
          let e = Str.match_end () in
          if s < end_pos then (
            apply_state_range s (min e end_pos);
            loop e)
          else ()
        with Not_found -> ()
    in
    loop start_pos
  in
  begin try
    let _ = Str.search_forward states_re text 0 in
    let states_start = Str.match_end () in
    let states_end =
      try
        let semi = String.index_from text states_start ';' in
        semi
      with Not_found -> String.length text
    in
    highlight_states states_start states_end
  with Not_found -> ()
  end;
  begin try
    let _ = Str.search_forward trans_re text 0 in
    let trans_start = Str.match_end () in
    let rec loop_arrow pos =
      try
        let _ = Str.search_forward arrow_re text pos in
        let g1_s = Str.group_beginning 1 in
        let g1_e = Str.group_end 1 in
        let g2_s = Str.group_beginning 2 in
        let g2_e = Str.group_end 2 in
        (if g1_s >= trans_start then apply_state_range g1_s g1_e);
        (if g2_s >= trans_start then apply_state_range g2_s g2_e);
        loop_arrow (Str.match_end ())
      with Not_found -> ()
    in
    let rec loop_src pos =
      try
        let _ = Str.search_forward src_group_re text pos in
        let s = Str.group_beginning 1 in
        let e = Str.group_end 1 in
        if s >= trans_start then apply_state_range s e;
        loop_src (Str.match_end ())
      with Not_found -> ()
    in
    let rec loop_to pos =
      try
        let _ = Str.search_forward to_re text pos in
        let s = Str.group_beginning 1 in
        let e = Str.group_end 1 in
        if s >= trans_start then apply_state_range s e;
        loop_to (Str.match_end ())
      with Not_found -> ()
    in
    loop_arrow trans_start;
    loop_src trans_start;
    loop_to trans_start
  with Not_found -> ()
  end;
  ()

let highlight_obc_range ~(buf : GText.buffer) ~start_offset ~keyword_tag ~type_tag ~number_tag
    ~comment_tag ~state_tag text =
  let start_iter = buf#start_iter#forward_chars start_offset in
  let end_iter = buf#start_iter#forward_chars (start_offset + String.length text) in
  buf#remove_all_tags ~start:start_iter ~stop:end_iter;
  let keywords =
    [
      "node";
      "returns";
      "guarantee";
      "assume";
      "contracts";
      "let";
      "locals";
      "states";
      "invariants";
      "invariant";
      "in";
      "init";
      "trans";
      "transitions";
      "when";
      "from";
      "to";
      "always";
      "next";
      "G";
      "X";
      "requires";
      "ensures";
      "if";
      "assumes";
      "guarantees";
      "then";
      "else";
      "end";
      "match";
      "with";
      "skip";
    ]
  in
  let types = [ "int"; "bool" ] in
  let number_re = Str.regexp "\\b[0-9]+\\b" in
  let comment_re = Str.regexp "(\\*.*\\*)" in
  ignore (Ide_text_utils.apply_words_range buf ~base:start_offset text keyword_tag keywords);
  ignore (Ide_text_utils.apply_words_range buf ~base:start_offset text type_tag types);
  ignore (Ide_text_utils.apply_regex_range buf ~base:start_offset text number_tag number_re);
  ignore (Ide_text_utils.apply_regex_range buf ~base:start_offset text comment_tag comment_re);
  let states_re = Str.regexp "\\bstates\\b" in
  let trans_re = Str.regexp "\\btrans\\(?:itions\\)?\\b" in
  let id_re = Str.regexp "\\b[A-Za-z_][A-Za-z0-9_]*\\b" in
  let arrow_re =
    Str.regexp
      "\\b\\([A-Za-z_][A-Za-z0-9_]*\\)\\b[ \t\r\n]*->[ \t\r\n]*\\b\\([A-Za-z_][A-Za-z0-9_]*\\)\\b"
  in
  let src_group_re =
    Str.regexp "\\(?:^\\|[\n\r]\\)[ \t]*\\([A-Za-z_][A-Za-z0-9_]*\\)[ \t]*:"
  in
  let to_re = Str.regexp "\\bto\\s+\\([A-Za-z_][A-Za-z0-9_]*\\)\\b" in
  let apply_state_range s e =
    let it_s = buf#start_iter#forward_chars (start_offset + s) in
    let it_e = buf#start_iter#forward_chars (start_offset + e) in
    buf#apply_tag state_tag ~start:it_s ~stop:it_e
  in
  begin
    try
      let _ = Str.search_forward states_re text 0 in
      let states_start = Str.match_end () in
      let states_end =
        try String.index_from text states_start ';' with Not_found -> String.length text
      in
      let rec loop pos =
        if pos >= states_end then ()
        else
          try
            let _ = Str.search_forward id_re text pos in
            let s = Str.match_beginning () in
            let e = Str.match_end () in
            if s < states_end then (
              apply_state_range s (min e states_end);
              loop e)
            else ()
          with Not_found -> ()
      in
      loop states_start
    with Not_found -> ()
  end;
  begin
    try
      let _ = Str.search_forward trans_re text 0 in
      let trans_start = Str.match_end () in
      let rec loop_arrow pos =
        try
          let _ = Str.search_forward arrow_re text pos in
          let g1_s = Str.group_beginning 1 in
          let g1_e = Str.group_end 1 in
          let g2_s = Str.group_beginning 2 in
          let g2_e = Str.group_end 2 in
          if g1_s >= trans_start then apply_state_range g1_s g1_e;
          if g2_s >= trans_start then apply_state_range g2_s g2_e;
          loop_arrow (Str.match_end ())
        with Not_found -> ()
      in
      let rec loop_src pos =
        try
          let _ = Str.search_forward src_group_re text pos in
          let s = Str.group_beginning 1 in
          let e = Str.group_end 1 in
          if s >= trans_start then apply_state_range s e;
          loop_src (Str.match_end ())
        with Not_found -> ()
      in
      let rec loop_to pos =
        try
          let _ = Str.search_forward to_re text pos in
          let s = Str.group_beginning 1 in
          let e = Str.group_end 1 in
          if s >= trans_start then apply_state_range s e;
          loop_to (Str.match_end ())
        with Not_found -> ()
      in
      loop_arrow trans_start;
      loop_src trans_start;
      loop_to trans_start
    with Not_found -> ()
  end;
  ()

let highlight_why_buf_impl buf text ~keyword_tag ~comment_tag ~number_tag ~type_tag =
  let start_iter = buf#start_iter in
  let end_iter = buf#end_iter in
  buf#remove_all_tags ~start:start_iter ~stop:end_iter;
  let apply_regex = apply_regex_to_buf buf text in
  let keywords =
    [
      "theory";
      "end";
      "use";
      "namespace";
      "let";
      "function";
      "predicate";
      "axiom";
      "goal";
      "forall";
      "exists";
      "if";
      "then";
      "else";
      "match";
      "with";
      "type";
      "clone";
      "import";
      "module";
    ]
  in
  let types = [ "int"; "bool"; "real" ] in
  let number_re = Str.regexp "\\b[0-9]+\\b" in
  let comment_re = Str.regexp "(\\*.*\\*)" in
  ignore (apply_words buf text keyword_tag keywords);
  ignore (apply_words buf text type_tag types);
  ignore (apply_regex number_tag number_re);
  ignore (apply_regex comment_tag comment_re)

let highlight_smt buf text ~keyword_tag ~type_tag ~number_tag ~comment_tag =
  let start_iter = buf#start_iter in
  let end_iter = buf#end_iter in
  buf#remove_all_tags ~start:start_iter ~stop:end_iter;
  let apply_regex = apply_regex_to_buf buf text in
  let keywords =
    [
      "assert";
      "check-sat";
      "check-sat-assuming";
      "declare-fun";
      "declare-const";
      "define-fun";
      "define-fun-rec";
      "define-const";
      "set-logic";
      "set-option";
      "push";
      "pop";
      "get-model";
      "get-value";
      "get-unsat-core";
      "get-proof";
      "exit";
      "forall";
      "exists";
      "let";
      "ite";
      "match";
      "as";
      "par";
      "declare-datatype";
      "declare-datatypes";
    ]
  in
  let types = [ "Int"; "Bool"; "Real" ] in
  let number_re = Str.regexp "\\b-?[0-9]+\\b" in
  let comment_re = Str.regexp ";[^\n]*" in
  ignore (apply_words buf text keyword_tag keywords);
  ignore (apply_words buf text type_tag types);
  ignore (apply_regex number_tag number_re);
  ignore (apply_regex comment_tag comment_re)
