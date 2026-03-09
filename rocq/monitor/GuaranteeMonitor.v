From Kairos.monitor Require Import MonitorSig.

Set Implicit Arguments.

Module Type GUARANTEE_MONITOR_SIG (G : MONITOR_SIG).
  Definition AvoidG (w : G.stream G.Obs) : Prop := G.avoids_bad w.
End GUARANTEE_MONITOR_SIG.
