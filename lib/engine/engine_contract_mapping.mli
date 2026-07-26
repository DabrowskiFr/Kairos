module Contract = Kairos_engine_contract.Contract

val proof_encoding_to_internal :
  Contract.proof_encoding -> Pipeline_types.proof_encoding

val proof_optimizations_to_internal :
  Contract.proof_optimizations -> Pipeline_types.proof_optimizations

val config_to_internal : Contract.config -> Pipeline_types.config
val error_to_contract : Pipeline_types.error -> Contract.error

val automata_outputs_to_contract :
  Pipeline_types.automata_outputs -> Contract.automata_outputs

val why_outputs_to_contract : Pipeline_types.why_outputs -> Contract.why_outputs

val obligations_outputs_to_contract :
  Pipeline_types.obligations_outputs -> Contract.obligations_outputs

val cost_report_outputs_to_contract :
  Pipeline_types.cost_report_outputs -> Contract.cost_report_outputs

val outputs_to_contract : Pipeline_types.outputs -> Contract.outputs
