
module CLA_16bit(
    input logic[15:0] A, B,
    input logic cin,
    output logic[15:0] Sum,
    output logic cout
    );

    logic[15:0] SUM;
    logic[16:0] C;
        assign C[0] = cin;
        assign C[4] = G_BLOCK[0] | (P_BLOCK[0] & C[0]);
        assign C[8] = G_BLOCK[1] | (P_BLOCK[1] & G_BLOCK[0]) | (P_BLOCK[1] & P_BLOCK[0] & C[0]);
        assign C[12] = G_BLOCK[2] | (P_BLOCK[2] & G_BLOCK[1]) | (P_BLOCK[2] & P_BLOCK[1] & G_BLOCK[0]) | (P_BLOCK[2] & P_BLOCK[1] & P_BLOCK[0] & C[0]);
    logic[3:0] P_BLOCK;
    logic[3:0] G_BLOCK;

    CLA_4bit nib1(
        .A(A[3:0]), 
        .B(B[3:0]), 
        .cin(C[0]),
        .Sum(SUM[3:0]), 
        .cout(),
        .G_block(G_BLOCK[0]), 
        .P_block(P_BLOCK[0])
        );
    
    CLA_4bit nib2(
        .A(A[7:4]), 
        .B(B[7:4]), 
        .cin(C[4]),
        .Sum(SUM[7:4]), 
        .cout(), 
        .G_block(G_BLOCK[1]), 
        .P_block(P_BLOCK[1])
        );

    CLA_4bit nib3(
        .A(A[11:8]), 
        .B(B[11:8]), 
        .cin(C[8]),
        .Sum(SUM[11:8]), 
        .cout(),
        .G_block(G_BLOCK[2]), 
        .P_block(P_BLOCK[2])
        );

    CLA_4bit nib4(
        .A(A[15:12]), 
        .B(B[15:12]), 
        .cin(C[12]),
        .Sum(SUM[15:12]), 
        .cout(C[16]),
        .G_block(G_BLOCK[3]), 
        .P_block(P_BLOCK[3])
        );

    assign Sum = SUM;
    assign cout = C[16];

endmodule
