
module CLA_4bit(
    input logic[3:0] A,
    input logic[3:0] B,
    input logic cin,
    output logic[3:0] Sum,
    output logic cout, P_block, G_block
    );

    logic [3:0] G, P;
    logic [4:0] C;

    assign G = A & B;
    assign P = A ^ B;
    assign P_block = P[3] & P[2] & P[1] & P[0];
    assign G_block = G[3] | (P[3] & G[2]) | (P[3] & P[2] & G[1]) | (P[3] & P[2] & P[1] & G[0]);


    assign C[0] = cin;
    assign C[1] = G[0] | (P[0] & C[0]);
    assign C[2] = G[1] | (P[1] & G[0]) | (P[1] & P[0] & C[0]);
    assign C[3] = G[2] | (P[2] & G[1]) | (P[2] & P[1] & G[0]) | (P[2] & P[1] & P[0] & C[0]);
    assign C[4] = G_block | (P_block & C[0]);

    assign cout = C[4];
    assign Sum = P ^ C[3:0];

endmodule