(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let format_text (text : string) : string =
  let lines = String.split_on_char '\n' text in
  let fmt_lines =
    List.map
      (fun s ->
        let t = String.trim s in
        if t = "" then "" else t)
      lines
  in
  String.concat "\n" fmt_lines
