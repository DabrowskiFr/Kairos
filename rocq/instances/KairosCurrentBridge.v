From Kairos Require Import KairosModularIntegration.

Set Implicit Arguments.

Module Type KAIROS_CURRENT_BRIDGE_SIG.
  Declare Module X : KAIROS_ORACLE_INSTANCE_SIG.
  Module B := KairosModularBridge X.
End KAIROS_CURRENT_BRIDGE_SIG.
