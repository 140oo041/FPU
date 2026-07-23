module rounder(
    input wire[7:0] mantissa_in,
    input wire[8:0] exp_in,
    input wire G, R, S,
    output reg[6:0] mantissa_out,
    output reg[7:0] exp_out,
    output reg flag_overflow
    );

    reg round_up;
    reg[8:0] rounded_mantissa;
    
    reg[8:0] temp_exp; 

    always @(*) begin
        if(exp_in == 9'd0) begin
            round_up = mantissa_in[7] & (|mantissa_in[6:0] | G | R | S);
            mantissa_out = 7'b0;
            temp_exp = round_up ? 9'd1 : 9'd0;
        end 
        
        else begin
            round_up = G & (R | S | mantissa_in[0]);
            rounded_mantissa = {1'b0, mantissa_in} + {8'b0, round_up};

            if(rounded_mantissa[8]) begin
                mantissa_out = rounded_mantissa[7:1];
                temp_exp = exp_in + 9'd1;
            end else begin
                mantissa_out = rounded_mantissa[6:0];
                temp_exp = exp_in;
            end
        end

        flag_overflow = temp_exp[8] | (&temp_exp[7:0]);
        exp_out = temp_exp[7:0];
    end

endmodule