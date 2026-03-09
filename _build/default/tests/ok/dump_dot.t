  $ kairos --log-level quiet --dump-dot - ./inputs/delay_int.kairos | grep -nE "digraph LTLResidual|r1 -> r1|label=\"\\{y\\} = pre\\(x\\)\"|r1 \\[shape=circle,label=\"1\"\\]"
  1:digraph LTLResidual {
  4:    r1 [shape=circle,label="1"];
  7:    r1 -> r1 [label="y = pre(x)"];
