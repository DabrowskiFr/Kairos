(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

let monitor_log_enabled : bool =
  match Sys.getenv_opt "OBCWHY3_LOG_MONITOR" with
  | Some ("1" | "true" | "yes") -> true
  | _ -> false

let log_monitor fmt =
  Printf.ksprintf
    (fun s ->
       if monitor_log_enabled then
         prerr_endline ("[monitor] " ^ s))
    fmt
