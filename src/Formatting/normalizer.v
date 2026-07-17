
module normalizer(
    input wire[11:0] mant_in,
    input wire[8:0] exp_in,
    output reg[7:0] mantissa_out,
    output reg[8:0] exp_out,
    output reg G, R, S,
    output reg flag_underflow
    );

    reg[3:0] shift_amt;
    reg[11:0] shifted;
    
    always @(*) begin
        if(mant_in[11]) begin
            shifted = {1'b0, mant_in[11:2], mant_in[1] | mant_in[0]};
            exp_out = exp_in + 9'd1;
        end
        
        else begin
            casez(mant_in[10:0])
                11'b1??????????: shift_amt = 4'd0;
                11'b01?????????: shift_amt = 4'd1;
                11'b001????????: shift_amt = 4'd2;
                11'b0001???????: shift_amt = 4'd3;
                11'b00001??????: shift_amt = 4'd4;
                11'b000001?????: shift_amt = 4'd5;
                11'b0000001????: shift_amt = 4'd6;
                11'b00000001???: shift_amt = 4'd7;
                11'b000000001??: shift_amt = 4'd8;
                11'b0000000001?: shift_amt = 4'd9;
                11'b00000000001: shift_amt = 4'd10;
                default: shift_amt = 4'd0;
            endcase
            
            flag_underflow = shift_amt >= exp_in;

            shifted = mant_in << shift_amt;
            exp_out = exp_in - shift_amt;
        end

        mantissa_out = shifted[10:3];
        G = shifted[2];
        R = shifted[1];
        S = shifted[0];
    end

endmodule