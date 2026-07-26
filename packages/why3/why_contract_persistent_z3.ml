(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

open Why3
open Why_contract_unix_io

type session = {
  pid : int;
  stdin_fd : Unix.file_descr;
  stdout_fd : Unix.file_descr;
  stderr_fd : Unix.file_descr;
  mutable stdout_pending : string;
  mutable stderr_pending : string;
  mutable closed : bool;
}

type runner = {
  timeout_s : float;
  argv : string array;
  mutable session : session option;
}

let shell_words command =
  let len = String.length command in
  let is_space = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false in
  let push_word words buffer =
    if Buffer.length buffer = 0 then words
    else
      let word = Buffer.contents buffer in
      Buffer.clear buffer;
      word :: words
  in
  let rec loop words buffer quote i =
    if i >= len then List.rev (push_word words buffer)
    else
      match (quote, command.[i]) with
      | None, c when is_space c ->
          loop (push_word words buffer) buffer None (i + 1)
      | None, '\'' -> loop words buffer (Some '\'') (i + 1)
      | None, '"' -> loop words buffer (Some '"') (i + 1)
      | Some '\'', '\'' -> loop words buffer None (i + 1)
      | Some '"', '"' -> loop words buffer None (i + 1)
      | _, '\\' when i + 1 < len ->
          Buffer.add_char buffer command.[i + 1];
          loop words buffer quote (i + 2)
      | _, c ->
          Buffer.add_char buffer c;
          loop words buffer quote (i + 1)
  in
  loop [] (Buffer.create (String.length command)) None 0

let word_contains_placeholder word =
  string_contains_substring ~needle:"%f" word
  || string_contains_substring ~needle:"%t" word

let argv_of_command command =
  match shell_words command with
  | [] -> [| "z3"; "-smt2"; "-in" |]
  | exe :: args ->
      let args =
        args
        |> List.filter (fun arg -> not (word_contains_placeholder arg))
        |> List.filter (fun arg -> arg <> "-T:%t")
      in
      let args =
        if List.exists (( = ) "-smt2") args then args else "-smt2" :: args
      in
      Array.of_list (exe :: args @ [ "-in" ])

let open_session ~(argv : string array) () : session =
  let t_spawn = Unix.gettimeofday () in
  let child_stdin_read, parent_stdin_write = create_pipe_noerr () in
  let parent_stdout_read, child_stdout_write = create_pipe_noerr () in
  let parent_stderr_read, child_stderr_write = create_pipe_noerr () in
  let pid =
    Unix.create_process argv.(0) argv child_stdin_read child_stdout_write
      child_stderr_write
  in
  List.iter close_fd_noerr
    [ child_stdin_read; child_stdout_write; child_stderr_write ];
  External_timing.record_why3_spawn
    ~elapsed_s:(Unix.gettimeofday () -. t_spawn);
  {
    pid;
    stdin_fd = parent_stdin_write;
    stdout_fd = parent_stdout_read;
    stderr_fd = parent_stderr_read;
    stdout_pending = "";
    stderr_pending = "";
    closed = false;
  }

let kill_session (session : session) =
  if not session.closed then begin
    session.closed <- true;
    (try Unix.kill session.pid Sys.sigkill with _ -> ());
    List.iter close_fd_noerr
      [ session.stdin_fd; session.stdout_fd; session.stderr_fd ];
    (try ignore (Unix.waitpid [] session.pid) with _ -> ())
  end

let waitpid_nohang pid =
  try
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ -> false
    | _ -> true
  with Unix.Unix_error (Unix.ECHILD, _, _) -> true

let rec waitpid_until ~deadline_s pid =
  if waitpid_nohang pid then true
  else if Unix.gettimeofday () >= deadline_s then false
  else begin
    ignore (Unix.select [] [] [] 0.01);
    waitpid_until ~deadline_s pid
  end

let close_session (session : session) =
  if not session.closed then begin
    session.closed <- true;
    (try write_string_fd session.stdin_fd "(exit)\n" with _ -> ());
    close_fd_noerr session.stdin_fd;
    let exited =
      waitpid_until ~deadline_s:(Unix.gettimeofday () +. 0.2) session.pid
    in
    if not exited then begin
      (try Unix.kill session.pid Sys.sigkill with _ -> ());
      (try ignore (Unix.waitpid [] session.pid) with _ -> ())
    end;
    List.iter close_fd_noerr
      [ session.stdout_fd; session.stderr_fd ]
  end

let create ~(timeout_s : float) ~(command : string) : runner =
  {
    timeout_s = max 1.0 timeout_s;
    argv = argv_of_command command;
    session = None;
  }

let close runner =
  match runner.session with
  | None -> ()
  | Some session ->
      runner.session <- None;
      close_session session

let restart runner =
  match runner.session with
  | None -> ()
  | Some session ->
      runner.session <- None;
      kill_session session

let session runner =
  match runner.session with
  | Some session when not session.closed -> session
  | _ ->
      let session = open_session ~argv:runner.argv () in
      runner.session <- Some session;
      session

let take_line_from_pending text =
  match String.index_opt text '\n' with
  | None -> None
  | Some idx ->
      let line = String.sub text 0 idx in
      let rest = String.sub text (idx + 1) (String.length text - idx - 1) in
      Some (line, rest)

let append_read_available fd pending =
  let bytes = Bytes.create 4096 in
  match Unix.read fd bytes 0 (Bytes.length bytes) with
  | 0 -> raise End_of_file
  | n -> pending ^ Bytes.sub_string bytes 0 n

let read_stderr session =
  try
    session.stderr_pending <-
      append_read_available session.stderr_fd session.stderr_pending
  with _ -> ()

let read_line session ~deadline_s =
  let rec loop () =
    match take_line_from_pending session.stdout_pending with
    | Some (line, rest) ->
        session.stdout_pending <- rest;
        Some line
    | None ->
        let remaining = deadline_s -. Unix.gettimeofday () in
        if remaining <= 0.0 then None
        else
          let read_fds = [ session.stdout_fd; session.stderr_fd ] in
          match Unix.select read_fds [] [] remaining with
          | [], _, _ -> None
          | ready, _, _ ->
              if List.mem session.stderr_fd ready then read_stderr session;
              if List.mem session.stdout_fd ready then
                session.stdout_pending <-
                  append_read_available session.stdout_fd session.stdout_pending;
              loop ()
  in
  loop ()

let line_is_z3_status line =
  match String.trim line with "sat" | "unsat" | "unknown" -> true | _ -> false

let strip_smt_exit_lines text =
  text |> String.split_on_char '\n'
  |> List.filter (fun line -> String.trim line <> "(exit)")
  |> String.concat "\n"

let read_status session ~deadline_s =
  let rec loop seen =
    match read_line session ~deadline_s with
    | None -> None
    | Some line ->
        let trimmed = String.trim line in
        if line_is_z3_status trimmed then Some (trimmed, List.rev seen)
        else loop (line :: seen)
  in
  loop []

let read_unknown_reason session =
  try
    write_string_fd session.stdin_fd "(get-info :reason-unknown)\n";
    match read_line session ~deadline_s:(Unix.gettimeofday () +. 1.0) with
    | Some line -> Some (String.trim line)
    | None -> None
  with _ -> None

let answer_of_status ?reason status =
  match status with
  | "unsat" -> Call_provers.Valid
  | "sat" -> Call_provers.Invalid
  | "unknown" -> begin
      match reason with
      | Some reason
        when string_contains_substring ~needle:"timeout"
               (String.lowercase_ascii reason) ->
          Call_provers.Timeout
      | Some reason -> Call_provers.Unknown reason
      | None -> Call_provers.Unknown "z3 returned unknown"
    end
  | other -> Call_provers.Failure ("unexpected z3 status: " ^ other)

let prover_result ~answer ~output ~elapsed_s =
  {
    Call_provers.pr_answer = answer;
    pr_status = Unix.WEXITED 0;
    pr_output = output;
    pr_time = elapsed_s;
    pr_steps = -1;
    pr_models = [];
  }

let prove_buffer ~(runner : runner) ~(buffer : Buffer.t) :
    Call_provers.prover_result =
  let session = session runner in
  let t0 = Unix.gettimeofday () in
  let timeout_ms = int_of_float (runner.timeout_s *. 1000.0) in
  let script =
    Printf.sprintf "(reset)\n(set-option :timeout %d)\n%s\n" timeout_ms
      (strip_smt_exit_lines (Buffer.contents buffer))
  in
  try
    write_string_fd session.stdin_fd script;
    let deadline_s = Unix.gettimeofday () +. runner.timeout_s +. 2.0 in
    match read_status session ~deadline_s with
    | None ->
        restart runner;
        let elapsed_s = Unix.gettimeofday () -. t0 in
        prover_result ~answer:Call_provers.Timeout
          ~output:"persistent z3 did not answer before the communication timeout"
          ~elapsed_s
    | Some (status, prelude) ->
        let reason =
          if status = "unknown" then read_unknown_reason session else None
        in
        let elapsed_s = Unix.gettimeofday () -. t0 in
        let reason_lines =
          match reason with Some reason -> [ reason ] | None -> []
        in
        let stderr_lines =
          if session.stderr_pending = "" then [] else [ session.stderr_pending ]
        in
        let output =
          String.concat "\n" (prelude @ [ status ] @ reason_lines @ stderr_lines)
        in
        let answer = answer_of_status ?reason status in
        prover_result ~answer ~output ~elapsed_s
  with exn ->
    restart runner;
    prover_result
      ~answer:(Call_provers.Failure (Printexc.to_string exn))
      ~output:(Printexc.to_string exn)
      ~elapsed_s:(Unix.gettimeofday () -. t0)
