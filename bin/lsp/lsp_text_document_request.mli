(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Resolve text-document requests against the open document store. *)

type document = {
  uri : string;
  text : string;
}

type positioned = {
  uri : string;
  text : string;
  line : int;
  character : int;
}

val document : Lsp_document_store.t -> Yojson.Safe.t -> document option
val positioned : Lsp_document_store.t -> Yojson.Safe.t -> positioned option
