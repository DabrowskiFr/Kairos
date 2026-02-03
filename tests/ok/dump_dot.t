  $ obc2why3 --log-level quiet --dump-dot - ./inputs/delay_int.obc | grep -nE "digraph LTLResidual|r1 -> r1|label=\"G\\(\\{y\\} = pre\\(x\\)\\)\""
  1:digraph LTLResidual {
  4:    r1 [shape=circle,label="G({y} = pre(x))"];
  7:    r1 -> r1 [label="{y} = pre(x)"];
