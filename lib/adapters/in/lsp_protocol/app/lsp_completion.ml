(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let completion_items_for_text (text : string) : string list =
  let tbl = Hashtbl.create 256 in
  let push s = if String.length s > 0 then Hashtbl.replace tbl s () in
  let keywords =
    [
      "node";
      "returns";
      "contracts";
      "ensures";
      "requires";
      "assumes";
      "guarantees";
      "locals";
      "ghosts";
      "observers";
      "states";
      "invariants";
      "except";
      "transitions";
      "to";
      "end";
      "if";
      "then";
      "else";
      "match";
      "skip";
      "init";
      "step";
      "history";
      "self";
    ]
  in
  List.iter push keywords;
  begin
    match Lsp_symbols.semantic_symbols_for_text text with
    | Some symbols -> List.iter push symbols.all
    | None -> ()
  end;
  Hashtbl.to_seq_keys tbl |> List.of_seq |> List.sort_uniq String.compare
