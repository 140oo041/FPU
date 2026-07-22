                    
module fullAdder(
    input wire A, B, Cin,
    output wire sum, carry
    );

    assign sum = A ^ B ^ Cin;
    assign carry = (Cin & (A | B)) | (A & B);

endmodule

