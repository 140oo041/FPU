
module rounder(
    input wire[7:0] mantissa_in,
    input wire[8:0] exp_in,
    input wire G, R, S,
    output reg[7:0] mantissa_out,
    output reg[8:0] exp_out,
    output wire flag_overflow
    );

    reg round_up;
    reg[8:0] rounded_mantissa;
    assign flag_overflow = exp_out[8] | (&exp_out[7:0]); //Overflow or 255

    always @(*) begin
        round_up = G & (R | S | mantissa_in[0]);

        rounded_mantissa = {1'b0, mantissa_in} + {8'b0, round_up};

        if(rounded_mantissa[8]) begin
            mantissa_out = rounded_mantissa[8:1];
            exp_out = exp_in + 9'd1;
        end

        else begin
            mantissa_out = rounded_mantissa[7:0];
            exp_out = exp_in;
        end
    end

endmodule