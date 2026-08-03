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


module sign_gen(
    input wire a_greater,
    input wire a_b_equal,
    input wire A_sign,
    input wire B_sign,
    input wire[2:0] op,
    output reg sign
    );

    always @(*) begin
        case(op)
            `DIV, `MUL: sign = A_sign ^ B_sign;
            
            `ADD: begin
                if(A_sign == B_sign)
                    sign = A_sign;
                else if(a_b_equal)
                    sign = 1'b0;
                else
                    sign = a_greater ? A_sign : B_sign;
            end
            
            `SUB: begin
                if(A_sign != B_sign)
                    sign = A_sign;
                else if(a_b_equal)
                    sign = 1'b0;
                else
                    sign = a_greater ? A_sign : !B_sign;
            end
            
            `NEG: sign = !A_sign;
            `ABS: sign = 1'b0;
            `SLT: sign = 1'b0;
            `NOP: sign = 1'b0;
            
            default: sign = 1'b0;
        endcase
    end

endmodule