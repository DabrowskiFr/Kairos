(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type t = (string, string) Hashtbl.t

let create () = Hashtbl.create 32
let find t uri = Hashtbl.find_opt t uri
let replace t uri text = Hashtbl.replace t uri text
let remove t uri = Hashtbl.remove t uri
