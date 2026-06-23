(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let env_bool name =
  match Sys.getenv_opt name with
  | Some ("1" | "true" | "TRUE" | "yes" | "YES" | "on" | "ON") -> true
  | _ -> false

let enabled = env_bool "KAIROS_LSP_TRACE"

let file =
  Option.value (Sys.getenv_opt "KAIROS_LSP_TRACE_FILE")
    ~default:"/tmp/kairos-lsp-trace.log"

let line (who : string) (msg : string) : unit =
  if enabled then (
    let oc = open_out_gen [ Open_creat; Open_text; Open_append ] 0o644 file in
    let tm = Unix.localtime (Unix.gettimeofday ()) in
    Printf.fprintf oc "%04d-%02d-%02d %02d:%02d:%02d [%s] %s\n"
      (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min
      tm.tm_sec who msg;
    close_out_noerr oc)
