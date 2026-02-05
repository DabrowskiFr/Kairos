let build_utf8_map text =
  let len = String.length text in
  let map = Array.make (len + 1) 0 in
  let i = ref 0 in
  let j = ref 0 in
  while !i < len do
    map.(!i) <- !j;
    let c = Char.code text.[!i] in
    let step =
      if c land 0x80 = 0 then 1
      else if c land 0xE0 = 0xC0 then 2
      else if c land 0xF0 = 0xE0 then 3
      else if c land 0xF8 = 0xF0 then 4
      else 1
    in
    i := !i + step;
    j := !j + 1
  done;
  map.(len) <- !j;
  map

let char_offset map byte_offset =
  if byte_offset < 0 then 0
  else if byte_offset >= Array.length map then map.(Array.length map - 1)
  else map.(byte_offset)

let apply_words buf text tag words =
  let map = build_utf8_map text in
  List.iter
    (fun w ->
      let wlen = String.length w in
      let rec loop i =
        if i + wlen <= String.length text then
          if String.sub text i wlen = w
             && (i = 0 || not (Char.code text.[i - 1] |> fun c ->
                     (c >= Char.code 'A' && c <= Char.code 'Z')
                     || (c >= Char.code 'a' && c <= Char.code 'z')
                     || (c >= Char.code '0' && c <= Char.code '9')
                     || text.[i - 1] = '_'))
             && (i + wlen = String.length text || not (Char.code text.[i + wlen] |> fun c ->
                     (c >= Char.code 'A' && c <= Char.code 'Z')
                     || (c >= Char.code 'a' && c <= Char.code 'z')
                     || (c >= Char.code '0' && c <= Char.code '9')
                     || text.[i + wlen] = '_'))
          then (
            let s = char_offset map i in
            let e = char_offset map (i + wlen) in
            let it_s = buf#start_iter#forward_chars s in
            let it_e = buf#start_iter#forward_chars e in
            buf#apply_tag tag ~start:it_s ~stop:it_e;
            loop (i + wlen)
          ) else loop (i + 1)
      in
      loop 0)
    words

let apply_regex_to_buf buf text tag re =
  let map = build_utf8_map text in
  let rec loop pos =
    try
      let _ = Str.search_forward re text pos in
      let s_byte = Str.match_beginning () in
      let e_byte = Str.match_end () in
      let s = char_offset map s_byte in
      let e = char_offset map e_byte in
      let it_s = buf#start_iter#forward_chars s in
      let it_e = buf#start_iter#forward_chars e in
      buf#apply_tag tag ~start:it_s ~stop:it_e;
      loop e_byte
    with Not_found -> ()
  in
  loop 0

let apply_words_range buf ~base text tag words =
  let map = build_utf8_map text in
  List.iter
    (fun w ->
      let wlen = String.length w in
      let rec loop i =
        if i + wlen <= String.length text then
          if String.sub text i wlen = w
             && (i = 0 || not (Char.code text.[i - 1] |> fun c ->
                     (c >= Char.code 'A' && c <= Char.code 'Z')
                     || (c >= Char.code 'a' && c <= Char.code 'z')
                     || (c >= Char.code '0' && c <= Char.code '9')
                     || text.[i - 1] = '_'))
             && (i + wlen = String.length text || not (Char.code text.[i + wlen] |> fun c ->
                     (c >= Char.code 'A' && c <= Char.code 'Z')
                     || (c >= Char.code 'a' && c <= Char.code 'z')
                     || (c >= Char.code '0' && c <= Char.code '9')
                     || text.[i + wlen] = '_'))
          then (
            let s = base + char_offset map i in
            let e = base + char_offset map (i + wlen) in
            let it_s = buf#start_iter#forward_chars s in
            let it_e = buf#start_iter#forward_chars e in
            buf#apply_tag tag ~start:it_s ~stop:it_e;
            loop (i + wlen)
          ) else loop (i + 1)
      in
      loop 0)
    words

let apply_regex_range buf ~base text tag re =
  let map = build_utf8_map text in
  let rec loop pos =
    try
      let _ = Str.search_forward re text pos in
      let s_byte = Str.match_beginning () in
      let e_byte = Str.match_end () in
      let s = base + char_offset map s_byte in
      let e = base + char_offset map e_byte in
      let it_s = buf#start_iter#forward_chars s in
      let it_e = buf#start_iter#forward_chars e in
      buf#apply_tag tag ~start:it_s ~stop:it_e;
      loop e_byte
    with Not_found -> ()
  in
  loop 0
