`include "fpu_pkg.vh"

module fpu_core(
    input wire[15:0] A, B,
    input wire[2:0] op,
    output reg[15:0] result,
    output reg accumulate_enable,
    output wire flag_NAN, flag_overflow, flag_underflow
    );
    
    //UNPACKING
    wire A_sign;
        assign A_sign = A[15];
    wire B_sign;
        assign B_sign = B[15];

    wire[7:0] A_exp;
        assign A_exp = A[14:7];
    wire[7:0] B_exp;
        assign B_exp = B[14:7];

    wire[6:0] A_mant;
        assign A_mant = A[6:0];
    wire[6:0] B_mant;
        assign B_mant = B[6:0];

    //ERROR FLAGS
    wire flag_A_NAN;
        assign flag_A_NAN = (A[14:6] == 9'h1FF);
    wire flag_B_NAN;
        assign flag_B_NAN = (B[14:6] == 9'h1FF);

    wire A_is_inf;
        assign A_is_inf = (A[14:0] == 15'h7F80);
    wire B_is_inf;
        assign B_is_inf = (B[14:0] == 15'h7F80);

    wire flag_div_by_zero;
        assign flag_div_by_zero = (op == `DIV) && (A[14:0] != 0) && (B[14:0] == 0);

    //wire flag_NAN; output now
        assign flag_NAN = (flag_A_NAN || flag_B_NAN) ||
        // Infinity / Infinity
        ((op == `DIV) && (A[14:0] == 15'h7F80) && (B[14:0] == 15'h7F80)) ||
        
        // 0 / 0
        ((op == `DIV) && (A[14:0] == 15'h0000) && (B[14:0] == 15'h0000)) ||
        
        // 0 * Infinity or Infinity * 0
        ((op == `MUL) && (A[14:0] == 15'h0000) && (B[14:0] == 15'h7F80)) ||
        ((op == `MUL) && (A[14:0] == 15'h7F80) && (B[14:0] == 15'h0000)) ||
        
        // +Infinity + -Infinity
        ((op == `ADD) && (A[14:0] == 15'h7F80) && (B[14:0] == 15'h7F80) && (A[15] != B[15])) ||
        
        // Infinity - Infinity
        ((op == `SUB) && (A[14:0] == 15'h7F80) && (B[14:0] == 15'h7F80) && (A[15] == B[15]));                               

    //MAGNITUDE COMPARISON
    wire a_greater;
        assign a_greater = (A[14:0] > B[14:0]);
    wire a_b_equal;
        assign a_b_equal = (A[14:0] == B[14:0]);
    
    //SIGN GENERATION
    wire result_sign_wire;

    sign_gen signGen(
            .a_greater(a_greater),
            .a_b_equal(a_b_equal),
            .A_sign(A_sign),
            .B_sign(B_sign),
            .op(op),
            .sign(result_sign_wire)
        );
    
    //ALIGNMENT FOR ADD/SUB
    reg[7:0] exp_diff;
    reg[7:0] EXP_ADD_SUB_RAW;
    reg[7:0] mantissa_to_align;
    wire[2:0] GRS_ADD_SUB_PRE;
    
    reg[3:0] shift_amt;
    wire[7:0] aligned_mant;

    always @(*) begin
        if(a_greater) begin
            exp_diff = A_exp - B_exp;
            mantissa_to_align = {1'b1, B_mant};
            EXP_ADD_SUB_RAW = A_exp;
        end 
        
        else begin
            exp_diff = B_exp - A_exp;
            mantissa_to_align = {1'b1, A_mant};
            EXP_ADD_SUB_RAW = B_exp;
        end
        
        shift_amt = exp_diff >= 4'hF ? 4'hF : exp_diff[3:0];
    end

    alignment_shifter alignmentShifter(
            .mantissa_in(mantissa_to_align),
            .shift_amt(shift_amt),
            .mantissa_out(aligned_mant),
            .G(GRS_ADD_SUB_PRE[2]),
            .R(GRS_ADD_SUB_PRE[1]),
            .S(GRS_ADD_SUB_PRE[0])
        );
    
    //ADD/SUB MANTISSA CALC
    reg[11:0] MANT_ADD_SUB_RAW;

    wire[7:0] larger_mantissa;
        assign larger_mantissa = a_greater ? {|A_exp[14:0], A_mant} : {|A_exp[14:0], B_mant};
    
    reg eff_op;

    always @(*) begin
        eff_op = `ADD_EFF;

        if(op == `ADD && (A_sign != B_sign))
            eff_op = `SUB_EFF;
        else if(op == `ADD && (A_sign == B_sign))
            eff_op = `ADD_EFF;
        else if(op == `SUB && (A_sign != B_sign))
            eff_op = `ADD_EFF;
        else if((op == `SUB && (A_sign == B_sign)))
            eff_op = `SUB_EFF;
    end

    always @(*) begin
        if(eff_op == `ADD_EFF)
            MANT_ADD_SUB_RAW = {larger_mantissa, 3'b0} + {aligned_mant, GRS_ADD_SUB_PRE};
        else
            MANT_ADD_SUB_RAW = {larger_mantissa, 3'b0} - {aligned_mant, GRS_ADD_SUB_PRE}; 
    end

    //MULTIPLY/DIVIDE MANTISSA CALC
    wire[7:0] recip_B;
    
    dividerLUT LUT(
            .index(B_mant), .reciprocal(recip_B)
        );

    wire[7:0] dadda_wire;
        assign dadda_wire = (op == `MUL) ? {1'b1, B_mant} : recip_B;
    
    wire[15:0] row1, row2;
    
    dadda_multiplier daddaMultiplier(
            .a({1'b1, A_mant}),
            .b(dadda_wire),
            .factor1(row1),
            .factor2(row2)
        );
    
    wire[15:0] sum;
        assign sum = row1 + row2;
    
    wire[11:0] MANT_DIV_RAW; 
        assign MANT_DIV_RAW = {1'b0, sum[15], sum[14:8], sum[7], sum[6], |sum[5:0]};

    wire[11:0] MANT_MUL_RAW;
        assign MANT_MUL_RAW = {sum[15], sum[14], sum[13:7], sum[6], sum[5], |sum[4:0]};

    wire[11:0] MANT_MUL_DIV_RAW;
        assign MANT_MUL_DIV_RAW = (op == `MUL) ? MANT_MUL_RAW : MANT_DIV_RAW;

    //MULTIPLY/DIVIDE EXPONENT CALC
    wire[8:0] EXP_MUL_DIV_RAW;
        assign EXP_MUL_DIV_RAW = (op == `MUL) ? 
        ({1'b0, A_exp} + {1'b0, B_exp} - 9'd127): 
        ({1'b0, A_exp} - {1'b0, B_exp} + 9'd127);

    //NORMALIZING
    reg[11:0] norm_mant_wire;
    reg[8:0] norm_exp_wire;    

    always @(*) begin
        if(op == `ADD || op == `SUB) begin
            norm_mant_wire = MANT_ADD_SUB_RAW;
            norm_exp_wire = EXP_ADD_SUB_RAW;
        end

        else begin
            norm_mant_wire = MANT_MUL_DIV_RAW;
            norm_exp_wire = EXP_MUL_DIV_RAW;
        end
    end

    wire[2:0] GRS;
    wire[7:0] round_mant_wire;
    wire[8:0] round_exp_wire;

    normalizer normalizer_inst(
            .mant_in(norm_mant_wire),
            .exp_in(norm_exp_wire),
            .mantissa_out(round_mant_wire),
            .exp_out(round_exp_wire),
            .G(GRS[2]),
            .R(GRS[1]),
            .S(GRS[0]),
            .flag_underflow(flag_underflow)
        );

    //ROUNDING
    wire[6:0] result_mant_wire;
    wire[7:0] result_exp_wire;
    
    rounder rounder_inst(
            .mantissa_in(round_mant_wire),
            .exp_in(round_exp_wire),
            .G(GRS[2]),
            .R(GRS[1]),
            .S(GRS[0]),
            .mantissa_out(result_mant_wire),
            .exp_out(result_exp_wire),
            .flag_overflow(flag_overflow)
        );
    
    wire[15:0] arithmetic_result;
        assign arithmetic_result = {result_sign_wire, result_exp_wire, result_mant_wire};

    //SLT
    reg[15:0] SLT;
    
    always @(*) begin
        SLT = 16'h0000;
        
        if(A_sign == 1'b1 && B_sign == 1'b0)
            SLT = 16'h3F80;
        
        else if(A_sign == B_sign) begin
            if(A_sign == 1'b0 && !a_greater)
                SLT = 16'h3F80;
            if(A_sign == 1'b1 && a_greater)
                SLT = 16'h3F80;
        end

        if(a_b_equal)
            SLT = 16'h0000;
    end

    //FINAL RESULT MUXING
    wire is_arith;
    assign is_arith = (op==`ADD)||(op==`SUB)||(op==`MUL)||(op==`DIV);

    //Catches cases where exponent isn't changed but result is known to be 0 (SUB)
    wire result_is_zero;
        assign result_is_zero = is_arith && (round_mant_wire == 8'b0);

    always @(*) begin
        accumulate_enable = 1'b1;
        result = 16'b0;

        case(op)
            `ADD, `DIV, `MUL, `SUB: result = arithmetic_result;
            `NEG: result = {~A_sign, A_exp, A_mant};
            `ABS: result = {1'b0, A_exp, A_mant};
            `SLT: result = SLT;
            `NOP: accumulate_enable = 1'b0;

            default: accumulate_enable = 1'b0;
        endcase

        if(is_arith && (flag_overflow || flag_div_by_zero))
            result = {result_sign_wire, 8'hFF, 7'h00};
        if(is_arith && flag_underflow)
            result = 16'b0;
        
        if(result_is_zero)
            result = 16'h0000;

        if(op == `DIV && A_is_inf && !B_is_inf)
            result = {result_sign_wire, 8'hFF, 7'h00};
        if(op == `DIV && B_is_inf && !A_is_inf)
            result = {result_sign_wire, 8'h00, 7'h00};
        if(op == `MUL && (A_is_inf || B_is_inf))
            result = {result_sign_wire, 8'hFF, 7'h00};

        if(flag_NAN)
            result = 16'h7FC0;
    end

endmodule
