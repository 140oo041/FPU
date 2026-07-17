
module RCA_9bit(
    input logic[8:0] A, B, 
    input logic Cin,
    output logic[8:0] sum,
    output logic cout
    );

    logic[9:0] C;
    assign C[0] = Cin;
    assign cout = C[9];

    genvar i;

    generate
        for(i = 0; i < 9; i++) begin: rca 
            fullAdder fa(
                .A(A[i]),
                .B(B[i]),
                .Cin(C[i]),
                .sum(sum[i]),
                .carry(C[i+1])
            );
        end
    endgenerate

endmodule