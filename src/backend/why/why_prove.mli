type summary = {
  total : int;
  valid : int;
  invalid : int;
  unknown : int;
  timeout : int;
  failure : int;
}

type result = {
  status : int;
  summary : summary;
}

val prove_file : ?timeout:int -> prover:string -> file:string -> unit -> result
