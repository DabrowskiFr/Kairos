(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Mutable document-store effects for synchronization notifications. *)

val apply_text_update :
  Lsp_document_store.t -> Lsp_document_sync_decode.text_update -> string

val text_for_save : Lsp_document_store.t -> string -> string
val close : Lsp_document_store.t -> string -> unit
