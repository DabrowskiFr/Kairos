val find_assoc :
  missing:('key -> 'error) ->
  'key ->
  ('key * 'value) list ->
  ('value, 'error) result

val all : ('a, 'error) result list -> ('a list, 'error) result

val map4 :
  length_mismatch:'error ->
  ('a -> 'b -> 'c -> 'd -> ('e, 'error) result) ->
  'a list ->
  'b list ->
  'c list ->
  'd list ->
  ('e list, 'error) result
