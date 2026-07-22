`include "fpu_pkg.vh"

module fpu_system(
    input clk,
    input reset_n,
    input data_ready,
    input wire[15:0] A, B,
    input wire[2:0] op,
    input acc,
    output reg[15:0] accumulate_register,
    output reg result_ready,
    output reg flag_NAN, flag_overflow, flag_underflow
    );

    wire [15:0] datapath_result;
    wire accumulate_register_enable;
    wire core_flag_NAN;
    wire core_flag_overflow;
    wire core_flag_underflow;    
     
    wire[15:0] input_a;
        assign input_a = acc ? accumulate_register : A;
        
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            accumulate_register <= 16'b0;
            result_ready <= 1'b0;
            flag_NAN <= 1'b0;
            flag_overflow <= 1'b0;
            flag_underflow <= 1'b0;
        end

        else if(data_ready) begin
            if(accumulate_register_enable) begin
                accumulate_register <= datapath_result;
            end
            
            flag_overflow <= core_flag_overflow;
            flag_underflow <= core_flag_underflow;
            flag_NAN <= core_flag_NAN;        
        end
        
        else begin
            result_ready <= 1'b0;
        end
    end

    fpu_core fpu_core(
        .A(input_a),
        .B(B),
        .op(op),
        .result(datapath_result),
        .accumulate_enable(accumulate_register_enable),
        .flag_NAN(core_flag_NAN),
        .flag_overflow(core_flag_overflow),
        .flag_underflow(core_flag_underflow)
    );

endmodule
