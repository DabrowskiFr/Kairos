(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Resolved symbol context for navigation-style LSP requests. *)

type t = {
  uri : string;
  text : string;
  ident : string;
  symbols : Lsp_symbols.semantic_symbols;
}

val resolve : Lsp_document_store.t -> Yojson.Safe.t -> t option
