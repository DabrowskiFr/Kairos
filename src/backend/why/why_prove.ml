let prove_file ?(timeout=30) ~(prover:string) ~(file:string) () : unit =
  let cmd =
    Printf.sprintf
      "why3 prove -a split_vc -a simplify_formula -P %s -t %d %s"
      prover timeout (Filename.quote file)
  in
  let status = Sys.command cmd in
  if status <> 0 then exit status
