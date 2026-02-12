let stage_label (stage : Stage_names.stage_id) : string =
  match stage with
  | Stage_names.Parsed -> "Parse OBC"
  | Stage_names.Automaton -> "Build monitor automaton"
  | Stage_names.Contracts -> "Check/Link user contracts"
  | Stage_names.Monitor -> "Monitor injection"
  | Stage_names.Obc -> "Emit OBC+"
  | Stage_names.Why -> "Emit Why3"
  | Stage_names.Prove -> "Why3 proof"

let stage_description (stage : Stage_names.stage_id) : string = Stage_names.description stage

let stage_items (stage : Stage_names.stage_id) : string list =
  match stage with
  | Stage_names.Parsed -> []
  | Stage_names.Automaton ->
      [ "normalize temporal atoms"; "build safety automaton"; "inline atom formulas" ]
  | Stage_names.Contracts ->
      [ "pair T to T' ensures with next T' to T'' requires"; "shift requires by one step" ]
  | Stage_names.Monitor ->
      [
        "inject monitor code into OBC";
        "add no-bad-state requires/ensures";
        "add program/monitor compatibility";
      ]
  | Stage_names.Obc -> [ "add ghost history variables"; "materialize pre_k as locals" ]
  | Stage_names.Why -> [ "build Why3 AST"; "emit Why3 code" ]
  | Stage_names.Prove -> [ "run why3 prove"; "summarize goals" ]
