`timescale 1ns / 1ps
`include "fpu_pkg.vh"

module datapath_tb();
    reg clk;
    reg reset_n;
    reg data_ready;
    reg [15:0] A;
    reg [15:0] B;
    reg [2:0] op;
    reg acc;

    wire [15:0] accumulate_register;
    wire result_ready;
    wire flag_NAN;
    wire flag_overflow;
    wire flag_underflow;
    
    
    fpu_system dut(
        .clk(clk),
        .reset_n(reset_n),
        .data_ready(data_ready),
        .A(A),
        .B(B),
        .op(op),
        .acc(acc),
        .accumulate_register(accumulate_register),
        .result_ready(result_ready),
        .flag_NAN(flag_NAN),
        .flag_overflow(flag_overflow),
        .flag_underflow(flag_underflow)
    );
    
    initial clk = 0;
    always #10 clk = ~clk;
    
    initial begin
        reset_n = 0;
        data_ready = 0;
        A = 16'h0000;
        B = 16'h0000;
        op = 3'b000;
        acc = 0;
        
        @(negedge clk);
        reset_n = 1;
        
        //MUL:
        @(negedge clk);
        A = 16'h4000;
        B = 16'h4040;
        op = `MUL; 
        data_ready = 1;
        
        #5 $display("Result_MUL: %h | EXPECTED: 16'h40C0", dut.datapath_result);
        
        @(negedge clk); 
        data_ready = 0;
        
        //DIV:
        @(negedge clk);
        A = 16'h40C0;
        B = 16'h4000;
        op = `DIV;
        data_ready = 1;
        
        #5 $display("Result_DIV: %h | EXPECTED: 16'h4040", dut.datapath_result);
        
        @(negedge clk);
        data_ready = 0;
        
        //ADD:
        @(negedge clk);
        A = 16'h4000;
        B = 16'h4080;
        op = `ADD;
        data_ready = 1;
                
//        #5
//        $display("LARGER_MANT: %b", dut.fpuCore.larger_mantissa);
//        $display("ALIGNED_MANT: %b\n", dut.fpuCore.aligned_mant);
//        $display("MANT_RAW: %b", dut.fpuCore.MANT_ADD_SUB_RAW);
//        $display("EXP_RAW: %b", dut.fpuCore.EXP_ADD_SUB_RAW);
//        $display("ROUND_MANT: %b", dut.fpuCore.round_mant_wire);
//        $display("ROUND_EXP: %b\n", dut.fpuCore.round_exp_wire);
//        $display("RES_EXP: %b", dut.fpuCore.result_exp_wire);
//        $display("RES_MANT: %b\n", dut.fpuCore.result_mant_wire);
        
        #5 $display("Result_ADD: %h | EXPECTED: 16'h40C0", dut.datapath_result);
        
        @(negedge clk); 
        data_ready = 0;

        //SUB:
        @(negedge clk); 
        A = 16'h40A0;
        B = 16'h4000;
        op = `SUB;
        data_ready = 1;
        
        #5 $display("Result_SUB: %h | EXPECTED: 16'h4040", dut.datapath_result);
        
        @(negedge clk); 
        data_ready = 0;
        
        //NOP: Shows 0 because that is the default result, but accumulate reg is still maintaned
        @(negedge clk);
        A = 16'h40A0;
        B = 16'h4000;
        op = `NOP;
        data_ready = 1;
 
        #5 $display("Result_NOP: %h | EXPECTED: 16'h4040", dut.datapath_result);
 
        @(negedge clk); 
        data_ready = 0;  
        
        //SLT:
        @(negedge clk);
        A = 16'h4000;
        B = 16'h40A0;
        op = `SLT;
        data_ready = 1;
 
        #5 $display("Result_SLT: %h | EXPECTED: 16'h3F80", dut.datapath_result);
 
        @(negedge clk); 
        data_ready = 0;
        
        //ABS: 
        @(negedge clk);
        A = 16'hE000;
        B = 16'h40A0;
        op = `ABS;
        data_ready = 1;

        #5 $display("Result_ABS: %h | EXPECTED: 16'h6000", dut.datapath_result);

        @(negedge clk); 
        data_ready = 0;

        //NEG:
        @(negedge clk);
        A = 16'hE000;
        B = 16'h40A0;
        op = `NEG;
        data_ready = 1;

        #5 $display("Result_NEG: %h | EXPECTED: 16'h6000", dut.datapath_result);

        @(negedge clk); 
        data_ready = 0;
        
        //ACC MUL (Just checking 1 acc operation for this simple tb):
        //Should effectively do h6000 * h40A0 = 16'h6120
        @(negedge clk);
        A = 16'hE000;
        B = 16'h40A0;
        op = `MUL;
        data_ready = 1;
        acc = 1'b1;

        #5 $display("Result_MUL_ACC: %h | EXPECTED: 16'h6120", dut.datapath_result);

        @(negedge clk); 
        data_ready = 0;

        $finish;
    end

endmodule
