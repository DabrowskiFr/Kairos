(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
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

let pp_data data =
  match data with
  | [] -> ""
  | items ->
      let parts = List.map (fun (k, v) -> k ^ "=" ^ v) items in
      " (" ^ String.concat ", " parts ^ ")"

let flow_info stage message data =
  let prefix = match stage with None -> "" | Some s -> s ^ ": " in
  Logs.debug (fun m -> m "[info] %s%s%s" prefix message (pp_data data))

let warning ?stage message =
  let prefix = match stage with None -> "" | Some s -> s ^ ": " in
  Logs.warn (fun m -> m "%s%s" prefix message)
