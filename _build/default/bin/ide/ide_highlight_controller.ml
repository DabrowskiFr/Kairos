let vcid_from_goal_index ~(goal_model : GTree.tree_store) ~(vcid_col : string GTree.column)
    (index : int option) : int option =
  match index with
  | None -> None
  | Some i -> (
      try
        let path = GTree.Path.create [ i ] in
        let row = goal_model#get_iter path in
        let vcid_s = goal_model#get ~row ~column:vcid_col in
        int_of_string_opt vcid_s
      with _ -> None)

let first_some = function Some _ as v -> v | None -> None
