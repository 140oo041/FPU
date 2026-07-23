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

    wire A_implicit = |A_exp;
    wire B_implicit = |B_exp;

    wire[7:0] A_mant_full = {A_implicit, A_mant & {7{A_implicit}}};
    wire[7:0] B_mant_full = {B_implicit, B_mant & {7{B_implicit}}};

    //ERROR FLAGS
    wire raw_overflow, raw_underflow, raw_NAN;

    wire flag_A_NAN;
        assign flag_A_NAN = (A_exp == 8'hFF) && (A_mant != 7'b0);
    wire flag_B_NAN;
        assign flag_B_NAN = (B_exp == 8'hFF) && (B_mant != 7'b0);
    wire either_nan;
        assign either_nan = flag_A_NAN || flag_B_NAN;

    //Don't check mantissa here because we flush subnormals to zero
    wire A_is_zero;
        assign A_is_zero = (A_exp == 8'h00);
    wire B_is_zero;
        assign B_is_zero = (B_exp == 8'h00);

    wire either_zero;
        assign either_zero = A_is_zero || B_is_zero;
    wire both_zero;
        assign both_zero = A_is_zero && B_is_zero;

    wire A_is_inf;
        assign A_is_inf = ({A_exp, A_mant} == 15'h7F80);
    wire B_is_inf;
        assign B_is_inf = ({B_exp, B_mant} == 15'h7F80);
    wire either_inf;
        assign either_inf = A_is_inf || B_is_inf;
    wire both_inf;
        assign both_inf = A_is_inf && B_is_inf;

    wire flag_div_by_zero;
        assign flag_div_by_zero = (op == `DIV) && (!A_is_zero) && B_is_zero;

    assign raw_NAN = either_nan ||
                    // Infinity / Infinity
                    ((op == `DIV) && both_inf) ||
                    
                    // 0 / 0
                    ((op == `DIV) && both_zero) ||
                    
                    // 0 * Infinity or Infinity * 0
                    ((op == `MUL) && ((A_is_zero && B_is_inf) ||
                                    (A_is_inf  && B_is_zero))) ||
                    
                    // +Infinity + -Infinity
                    ((op == `ADD) && both_inf && (A_sign != B_sign)) ||
                    
                    // Infinity - Infinity
                    ((op == `SUB) && both_inf && (A_sign == B_sign));

    //MAGNITUDE COMPARISON
    wire a_greater;
        assign a_greater = ({A_exp, A_mant} > {B_exp, B_mant});
    wire a_b_equal;
        assign a_b_equal = ({A_exp, A_mant} == {B_exp, B_mant});    
    
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
            mantissa_to_align = B_mant_full;
            EXP_ADD_SUB_RAW = A_exp;
        end 
        
        else begin
            exp_diff = B_exp - A_exp;
            mantissa_to_align = A_mant_full;
            EXP_ADD_SUB_RAW = B_exp;
        end
        
        shift_amt = (exp_diff >= 4'hF) ? 4'hF : exp_diff[3:0];
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
        assign larger_mantissa = a_greater ? A_mant_full : B_mant_full;
    
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
            .index(B_mant_full[6:0]), .reciprocal(recip_B)
        );

    wire recip_exact_pow2 = (B_mant_full[6:0] == 7'b0);

    wire[7:0] recip_B_fixed;
        assign recip_B_fixed = recip_exact_pow2 ? 8'b10000000 : recip_B;

    wire[7:0] dadda_wire;
        assign dadda_wire = (op == `MUL) ? B_mant_full : recip_B_fixed;
    
    wire[15:0] row1, row2;
    
    dadda_multiplier daddaMultiplier(
            .a(A_mant_full),
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
    reg[8:0] exp_mul_div_raw_reg;
    
    wire [8:0] mul_sum = {1'b0, A_exp} + {1'b0, B_exp};
    wire [8:0] div_sum = {1'b0, A_exp} + 9'd127 + {8'b0, recip_exact_pow2};

    always @(*) begin
        if(op == `MUL) begin
            if(mul_sum >= 9'd127) 
                exp_mul_div_raw_reg = mul_sum - 9'd127;
            else 
                exp_mul_div_raw_reg = 9'd0;
        end 

        else if(op == `DIV) begin
            if(div_sum >= {1'b0, B_exp}) 
                exp_mul_div_raw_reg = div_sum - {1'b0, B_exp};
            else 
                exp_mul_div_raw_reg = 9'd0;
        end 

        else begin
            exp_mul_div_raw_reg = 9'd0;
        end
    end

    wire[8:0] EXP_MUL_DIV_RAW;
        assign EXP_MUL_DIV_RAW = exp_mul_div_raw_reg;

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
            .flag_underflow(raw_underflow)
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
            .flag_overflow(raw_overflow)
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

        if(a_b_equal || either_nan)
            SLT = 16'h0000;
    end

//FINAL RESULT MUXING
    wire is_arith;
    assign is_arith = (op==`ADD)||(op==`SUB)||(op==`MUL)||(op==`DIV);

    wire result_is_zero;
        assign result_is_zero = is_arith && (round_mant_wire == 8'b0);

    wire deep_underflow_mul = (op == `MUL) && (mul_sum < 9'd127) && !either_zero;
    
    wire true_underflow = deep_underflow_mul || (raw_underflow && (result_exp_wire == 8'h00));
    
    wire div_overflow_bug = (op == `DIV) && !either_inf && !either_zero && 
                            ({1'b0, A_exp} >= ({1'b0, B_exp} + 9'd128)) && (A_mant >= B_mant);

    wire div_underflow_bug = (op == `DIV) && (A_mant == B_mant) && 
                             ({1'b0, A_exp} + 9'd126 == {1'b0, B_exp}) && 
                             !either_zero && !either_inf;

    wire will_round_up = GRS[2] & (GRS[1] | GRS[0] | round_mant_wire[0]); 
    wire mul_boundary_rescue = (op == `MUL) && (mul_sum == 9'd127) && (round_mant_wire == 8'h7F) && will_round_up;
    
    wire boundary_rescue = mul_boundary_rescue || div_underflow_bug;
    
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

        if(is_arith && (raw_overflow || div_overflow_bug || flag_div_by_zero))
            result = {result_sign_wire, 8'hFF, 7'h00};
        
        if(is_arith && true_underflow)
            result = {result_sign_wire, 15'b0};
        
        if(result_is_zero)
            result = {result_sign_wire, 15'b0};
        
        if(op == `DIV && A_is_inf && !B_is_inf)
            result = {result_sign_wire, 8'hFF, 7'h00};
        if(op == `DIV && B_is_inf && !A_is_inf)
            result = {result_sign_wire, 8'h00, 7'h00};

        if((op == `MUL || op == `ADD || op == `SUB) && either_inf)
            result = {result_sign_wire, 8'hFF, 7'h00};            
        
        if(op == `MUL && either_zero)
            result = {result_sign_wire, 15'b0};

        //Only arith compute (mul, div, add, sub) can trigger flags
        if(is_arith && flag_NAN)
            result = 16'h7FC0;
            
        if (boundary_rescue)
            result = {result_sign_wire, 15'h0080};
    end
    
    assign flag_overflow = is_arith ? ((raw_overflow || div_overflow_bug) && !either_inf && !flag_div_by_zero && !raw_NAN) : 1'b0;    
    
    assign flag_underflow = is_arith ? (true_underflow && !either_inf && !either_zero && !raw_NAN && !boundary_rescue) : 1'b0;    
    
    assign flag_NAN = is_arith ? raw_NAN : 1'b0;

endmodule