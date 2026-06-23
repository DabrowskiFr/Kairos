(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Resolve outline input texts from request payloads and open documents. *)

type t = {
  source_text : string;
  abstract_text : string;
}

val resolve : docs:Lsp_document_store.t -> Lsp_outline_decode.t -> t
