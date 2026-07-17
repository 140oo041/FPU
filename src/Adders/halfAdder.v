
module halfAdder(
    input wire A, B, 
    output wire sum, carry
    );

    assign sum = A ^ B;
    assign carry = A & B;

endmodule
