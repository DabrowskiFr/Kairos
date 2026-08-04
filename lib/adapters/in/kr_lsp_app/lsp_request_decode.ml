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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

let get_param_string (params : Yojson.Safe.t) key =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with Some (`String s) -> Some s | _ -> None)
  | _ -> None

let get_param_bool (params : Yojson.Safe.t) key default =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with Some (`Bool b) -> b | _ -> default)
  | _ -> default

let get_param_int (params : Yojson.Safe.t) key default =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with Some (`Int n) -> n | _ -> default)
  | _ -> default

let get_param_obj (params : Yojson.Safe.t) key =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with Some (`Assoc ys) -> Some ys | _ -> None)
  | _ -> None

let get_param_list (params : Yojson.Safe.t) key =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with Some (`List ys) -> Some ys | _ -> None)
  | _ -> None

let get_text_document_uri (params : Yojson.Safe.t) =
  match get_param_obj params "textDocument" with
  | Some td -> (
      match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
  | None -> None

let get_did_open_text (params : Yojson.Safe.t) =
  match get_param_obj params "textDocument" with
  | Some td -> (
      match List.assoc_opt "text" td with Some (`String s) -> Some s | _ -> None)
  | None -> None

let get_did_change_text (params : Yojson.Safe.t) =
  match get_param_list params "contentChanges" with
  | Some changes ->
      let rec last_text acc = function
        | [] -> acc
        | (`Assoc c) :: tl ->
            let next =
              match List.assoc_opt "text" c with
              | Some (`String s) -> Some s
              | _ -> acc
            in
            last_text next tl
        | _ :: tl -> last_text acc tl
      in
      last_text None changes
  | None -> None

let position_from_params (params : Yojson.Safe.t) : (int * int) option =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt "position" xs with
      | Some (`Assoc p) -> (
          match (List.assoc_opt "line" p, List.assoc_opt "character" p) with
          | Some (`Int l), Some (`Int c) -> Some (l, c)
          | _ -> None)
      | _ -> None)
  | _ -> None

let client_supports_work_done_progress (params : Yojson.Safe.t) : bool =
  match get_param_obj params "capabilities" with
  | Some caps -> (
      match List.assoc_opt "window" caps with
      | Some (`Assoc win) -> (
          match List.assoc_opt "workDoneProgress" win with
          | Some (`Bool b) -> b
          | _ -> false)
      | _ -> false)
  | None -> false
