
`ifndef FPU_PKG
`define FPU_PKG

// Opcodes
`define ADD 3'b000
`define SUB 3'b001
`define MUL 3'b010
`define DIV 3'b011
`define NEG 3'b100
`define ABS 3'b101
`define SLT 3'b110
`define NOP 3'b111

// Effective add/sub operations
`define ADD_EFF 1'b0
`define SUB_EFF 1'b1

`endif