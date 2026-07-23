
module dadda_multiplier(
	input wire[7:0] a, b,
	output wire[15:0] factor1, factor2
	);

	wire pp_0_0;
	assign pp_0_0 = a[0] & b[0];


	wire pp_0_1;
	assign pp_0_1 = a[0] & b[1];


	wire pp_0_2;
	assign pp_0_2 = a[0] & b[2];


	wire pp_0_3;
	assign pp_0_3 = a[0] & b[3];


	wire pp_0_4;
	assign pp_0_4 = a[0] & b[4];


	wire pp_0_5;
	assign pp_0_5 = a[0] & b[5];


	wire pp_0_6;
	assign pp_0_6 = a[0] & b[6];


	wire pp_0_7;
	assign pp_0_7 = a[0] & b[7];


	wire pp_1_0;
	assign pp_1_0 = a[1] & b[0];


	wire pp_1_1;
	assign pp_1_1 = a[1] & b[1];


	wire pp_1_2;
	assign pp_1_2 = a[1] & b[2];


	wire pp_1_3;
	assign pp_1_3 = a[1] & b[3];


	wire pp_1_4;
	assign pp_1_4 = a[1] & b[4];


	wire pp_1_5;
	assign pp_1_5 = a[1] & b[5];


	wire pp_1_6;
	assign pp_1_6 = a[1] & b[6];


	wire pp_1_7;
	assign pp_1_7 = a[1] & b[7];


	wire pp_2_0;
	assign pp_2_0 = a[2] & b[0];


	wire pp_2_1;
	assign pp_2_1 = a[2] & b[1];


	wire pp_2_2;
	assign pp_2_2 = a[2] & b[2];


	wire pp_2_3;
	assign pp_2_3 = a[2] & b[3];


	wire pp_2_4;
	assign pp_2_4 = a[2] & b[4];


	wire pp_2_5;
	assign pp_2_5 = a[2] & b[5];


	wire pp_2_6;
	assign pp_2_6 = a[2] & b[6];


	wire pp_2_7;
	assign pp_2_7 = a[2] & b[7];


	wire pp_3_0;
	assign pp_3_0 = a[3] & b[0];


	wire pp_3_1;
	assign pp_3_1 = a[3] & b[1];


	wire pp_3_2;
	assign pp_3_2 = a[3] & b[2];


	wire pp_3_3;
	assign pp_3_3 = a[3] & b[3];


	wire pp_3_4;
	assign pp_3_4 = a[3] & b[4];


	wire pp_3_5;
	assign pp_3_5 = a[3] & b[5];


	wire pp_3_6;
	assign pp_3_6 = a[3] & b[6];


	wire pp_3_7;
	assign pp_3_7 = a[3] & b[7];


	wire pp_4_0;
	assign pp_4_0 = a[4] & b[0];


	wire pp_4_1;
	assign pp_4_1 = a[4] & b[1];


	wire pp_4_2;
	assign pp_4_2 = a[4] & b[2];


	wire pp_4_3;
	assign pp_4_3 = a[4] & b[3];


	wire pp_4_4;
	assign pp_4_4 = a[4] & b[4];


	wire pp_4_5;
	assign pp_4_5 = a[4] & b[5];


	wire pp_4_6;
	assign pp_4_6 = a[4] & b[6];


	wire pp_4_7;
	assign pp_4_7 = a[4] & b[7];


	wire pp_5_0;
	assign pp_5_0 = a[5] & b[0];


	wire pp_5_1;
	assign pp_5_1 = a[5] & b[1];


	wire pp_5_2;
	assign pp_5_2 = a[5] & b[2];


	wire pp_5_3;
	assign pp_5_3 = a[5] & b[3];


	wire pp_5_4;
	assign pp_5_4 = a[5] & b[4];


	wire pp_5_5;
	assign pp_5_5 = a[5] & b[5];


	wire pp_5_6;
	assign pp_5_6 = a[5] & b[6];


	wire pp_5_7;
	assign pp_5_7 = a[5] & b[7];


	wire pp_6_0;
	assign pp_6_0 = a[6] & b[0];


	wire pp_6_1;
	assign pp_6_1 = a[6] & b[1];


	wire pp_6_2;
	assign pp_6_2 = a[6] & b[2];


	wire pp_6_3;
	assign pp_6_3 = a[6] & b[3];


	wire pp_6_4;
	assign pp_6_4 = a[6] & b[4];


	wire pp_6_5;
	assign pp_6_5 = a[6] & b[5];


	wire pp_6_6;
	assign pp_6_6 = a[6] & b[6];


	wire pp_6_7;
	assign pp_6_7 = a[6] & b[7];


	wire pp_7_0;
	assign pp_7_0 = a[7] & b[0];


	wire pp_7_1;
	assign pp_7_1 = a[7] & b[1];


	wire pp_7_2;
	assign pp_7_2 = a[7] & b[2];


	wire pp_7_3;
	assign pp_7_3 = a[7] & b[3];


	wire pp_7_4;
	assign pp_7_4 = a[7] & b[4];


	wire pp_7_5;
	assign pp_7_5 = a[7] & b[5];


	wire pp_7_6;
	assign pp_7_6 = a[7] & b[6];


	wire pp_7_7;
	assign pp_7_7 = a[7] & b[7];


	wire s6_c6_ha0_sum, s6_c6_ha0_carry;
	halfAdder HA_6_6_0(pp_0_6, pp_1_5, s6_c6_ha0_sum, s6_c6_ha0_carry);

	wire s6_c7_fa0_sum, s6_c7_fa0_carry;
	fullAdder FA_6_7_0(pp_0_7, pp_1_6, pp_2_5, s6_c7_fa0_sum, s6_c7_fa0_carry);

	wire s6_c7_ha0_sum, s6_c7_ha0_carry;
	halfAdder HA_6_7_0(pp_3_4, pp_4_3, s6_c7_ha0_sum, s6_c7_ha0_carry);

	wire s6_c8_fa0_sum, s6_c8_fa0_carry;
	fullAdder FA_6_8_0(pp_1_7, pp_2_6, pp_3_5, s6_c8_fa0_sum, s6_c8_fa0_carry);

	wire s6_c8_ha0_sum, s6_c8_ha0_carry;
	halfAdder HA_6_8_0(pp_4_4, pp_5_3, s6_c8_ha0_sum, s6_c8_ha0_carry);

	wire s6_c9_fa0_sum, s6_c9_fa0_carry;
	fullAdder FA_6_9_0(pp_2_7, pp_3_6, pp_4_5, s6_c9_fa0_sum, s6_c9_fa0_carry);

	wire s4_c4_ha0_sum, s4_c4_ha0_carry;
	halfAdder HA_4_4_0(pp_0_4, pp_1_3, s4_c4_ha0_sum, s4_c4_ha0_carry);

	wire s4_c5_fa0_sum, s4_c5_fa0_carry;
	fullAdder FA_4_5_0(pp_0_5, pp_1_4, pp_2_3, s4_c5_fa0_sum, s4_c5_fa0_carry);

	wire s4_c5_ha0_sum, s4_c5_ha0_carry;
	halfAdder HA_4_5_0(pp_3_2, pp_4_1, s4_c5_ha0_sum, s4_c5_ha0_carry);

	wire s4_c6_fa0_sum, s4_c6_fa0_carry;
	fullAdder FA_4_6_0(s6_c6_ha0_sum, pp_2_4, pp_3_3, s4_c6_fa0_sum, s4_c6_fa0_carry);

	wire s4_c6_fa1_sum, s4_c6_fa1_carry;
	fullAdder FA_4_6_1(pp_4_2, pp_5_1, pp_6_0, s4_c6_fa1_sum, s4_c6_fa1_carry);

	wire s4_c7_fa0_sum, s4_c7_fa0_carry;
	fullAdder FA_4_7_0(s6_c6_ha0_carry, s6_c7_fa0_sum, s6_c7_ha0_sum, s4_c7_fa0_sum, s4_c7_fa0_carry);

	wire s4_c7_fa1_sum, s4_c7_fa1_carry;
	fullAdder FA_4_7_1(pp_5_2, pp_6_1, pp_7_0, s4_c7_fa1_sum, s4_c7_fa1_carry);

	wire s4_c8_fa0_sum, s4_c8_fa0_carry;
	fullAdder FA_4_8_0(s6_c7_fa0_carry, s6_c7_ha0_carry, s6_c8_fa0_sum, s4_c8_fa0_sum, s4_c8_fa0_carry);

	wire s4_c8_fa1_sum, s4_c8_fa1_carry;
	fullAdder FA_4_8_1(s6_c8_ha0_sum, pp_6_2, pp_7_1, s4_c8_fa1_sum, s4_c8_fa1_carry);

	wire s4_c9_fa0_sum, s4_c9_fa0_carry;
	fullAdder FA_4_9_0(s6_c8_fa0_carry, s6_c8_ha0_carry, s6_c9_fa0_sum, s4_c9_fa0_sum, s4_c9_fa0_carry);

	wire s4_c9_fa1_sum, s4_c9_fa1_carry;
	fullAdder FA_4_9_1(pp_5_4, pp_6_3, pp_7_2, s4_c9_fa1_sum, s4_c9_fa1_carry);

	wire s4_c10_fa0_sum, s4_c10_fa0_carry;
	fullAdder FA_4_10_0(s6_c9_fa0_carry, pp_3_7, pp_4_6, s4_c10_fa0_sum, s4_c10_fa0_carry);

	wire s4_c10_fa1_sum, s4_c10_fa1_carry;
	fullAdder FA_4_10_1(pp_5_5, pp_6_4, pp_7_3, s4_c10_fa1_sum, s4_c10_fa1_carry);

	wire s4_c11_fa0_sum, s4_c11_fa0_carry;
	fullAdder FA_4_11_0(pp_4_7, pp_5_6, pp_6_5, s4_c11_fa0_sum, s4_c11_fa0_carry);

	wire s3_c3_ha0_sum, s3_c3_ha0_carry;
	halfAdder HA_3_3_0(pp_0_3, pp_1_2, s3_c3_ha0_sum, s3_c3_ha0_carry);

	wire s3_c4_fa0_sum, s3_c4_fa0_carry;
	fullAdder FA_3_4_0(s4_c4_ha0_sum, pp_2_2, pp_3_1, s3_c4_fa0_sum, s3_c4_fa0_carry);

	wire s3_c5_fa0_sum, s3_c5_fa0_carry;
	fullAdder FA_3_5_0(s4_c4_ha0_carry, s4_c5_fa0_sum, s4_c5_ha0_sum, s3_c5_fa0_sum, s3_c5_fa0_carry);

	wire s3_c6_fa0_sum, s3_c6_fa0_carry;
	fullAdder FA_3_6_0(s4_c5_fa0_carry, s4_c5_ha0_carry, s4_c6_fa0_sum, s3_c6_fa0_sum, s3_c6_fa0_carry);

	wire s3_c7_fa0_sum, s3_c7_fa0_carry;
	fullAdder FA_3_7_0(s4_c6_fa0_carry, s4_c6_fa1_carry, s4_c7_fa0_sum, s3_c7_fa0_sum, s3_c7_fa0_carry);

	wire s3_c8_fa0_sum, s3_c8_fa0_carry;
	fullAdder FA_3_8_0(s4_c7_fa0_carry, s4_c7_fa1_carry, s4_c8_fa0_sum, s3_c8_fa0_sum, s3_c8_fa0_carry);

	wire s3_c9_fa0_sum, s3_c9_fa0_carry;
	fullAdder FA_3_9_0(s4_c8_fa0_carry, s4_c8_fa1_carry, s4_c9_fa0_sum, s3_c9_fa0_sum, s3_c9_fa0_carry);

	wire s3_c10_fa0_sum, s3_c10_fa0_carry;
	fullAdder FA_3_10_0(s4_c9_fa0_carry, s4_c9_fa1_carry, s4_c10_fa0_sum, s3_c10_fa0_sum, s3_c10_fa0_carry);

	wire s3_c11_fa0_sum, s3_c11_fa0_carry;
	fullAdder FA_3_11_0(s4_c10_fa0_carry, s4_c10_fa1_carry, s4_c11_fa0_sum, s3_c11_fa0_sum, s3_c11_fa0_carry);

	wire s3_c12_fa0_sum, s3_c12_fa0_carry;
	fullAdder FA_3_12_0(s4_c11_fa0_carry, pp_5_7, pp_6_6, s3_c12_fa0_sum, s3_c12_fa0_carry);

	wire s2_c2_ha0_sum, s2_c2_ha0_carry;
	halfAdder HA_2_2_0(pp_0_2, pp_1_1, s2_c2_ha0_sum, s2_c2_ha0_carry);

	wire s2_c3_fa0_sum, s2_c3_fa0_carry;
	fullAdder FA_2_3_0(s3_c3_ha0_sum, pp_2_1, pp_3_0, s2_c3_fa0_sum, s2_c3_fa0_carry);

	wire s2_c4_fa0_sum, s2_c4_fa0_carry;
	fullAdder FA_2_4_0(s3_c3_ha0_carry, s3_c4_fa0_sum, pp_4_0, s2_c4_fa0_sum, s2_c4_fa0_carry);

	wire s2_c5_fa0_sum, s2_c5_fa0_carry;
	fullAdder FA_2_5_0(s3_c4_fa0_carry, s3_c5_fa0_sum, pp_5_0, s2_c5_fa0_sum, s2_c5_fa0_carry);

	wire s2_c6_fa0_sum, s2_c6_fa0_carry;
	fullAdder FA_2_6_0(s3_c5_fa0_carry, s3_c6_fa0_sum, s4_c6_fa1_sum, s2_c6_fa0_sum, s2_c6_fa0_carry);

	wire s2_c7_fa0_sum, s2_c7_fa0_carry;
	fullAdder FA_2_7_0(s3_c6_fa0_carry, s3_c7_fa0_sum, s4_c7_fa1_sum, s2_c7_fa0_sum, s2_c7_fa0_carry);

	wire s2_c8_fa0_sum, s2_c8_fa0_carry;
	fullAdder FA_2_8_0(s3_c7_fa0_carry, s3_c8_fa0_sum, s4_c8_fa1_sum, s2_c8_fa0_sum, s2_c8_fa0_carry);

	wire s2_c9_fa0_sum, s2_c9_fa0_carry;
	fullAdder FA_2_9_0(s3_c8_fa0_carry, s3_c9_fa0_sum, s4_c9_fa1_sum, s2_c9_fa0_sum, s2_c9_fa0_carry);

	wire s2_c10_fa0_sum, s2_c10_fa0_carry;
	fullAdder FA_2_10_0(s3_c9_fa0_carry, s3_c10_fa0_sum, s4_c10_fa1_sum, s2_c10_fa0_sum, s2_c10_fa0_carry);

	wire s2_c11_fa0_sum, s2_c11_fa0_carry;
	fullAdder FA_2_11_0(s3_c10_fa0_carry, s3_c11_fa0_sum, pp_7_4, s2_c11_fa0_sum, s2_c11_fa0_carry);

	wire s2_c12_fa0_sum, s2_c12_fa0_carry;
	fullAdder FA_2_12_0(s3_c11_fa0_carry, s3_c12_fa0_sum, pp_7_5, s2_c12_fa0_sum, s2_c12_fa0_carry);

	wire s2_c13_fa0_sum, s2_c13_fa0_carry;
	fullAdder FA_2_13_0(s3_c12_fa0_carry, pp_6_7, pp_7_6, s2_c13_fa0_sum, s2_c13_fa0_carry);

	assign factor1[0] = pp_0_0;
	assign factor2[0] = 1'b0;
	assign factor1[1] = pp_0_1;
	assign factor2[1] = pp_1_0;
	assign factor1[2] = s2_c2_ha0_sum;
	assign factor2[2] = pp_2_0;
	assign factor1[3] = s2_c2_ha0_carry;
	assign factor2[3] = s2_c3_fa0_sum;
	assign factor1[4] = s2_c3_fa0_carry;
	assign factor2[4] = s2_c4_fa0_sum;
	assign factor1[5] = s2_c4_fa0_carry;
	assign factor2[5] = s2_c5_fa0_sum;
	assign factor1[6] = s2_c5_fa0_carry;
	assign factor2[6] = s2_c6_fa0_sum;
	assign factor1[7] = s2_c6_fa0_carry;
	assign factor2[7] = s2_c7_fa0_sum;
	assign factor1[8] = s2_c7_fa0_carry;
	assign factor2[8] = s2_c8_fa0_sum;
	assign factor1[9] = s2_c8_fa0_carry;
	assign factor2[9] = s2_c9_fa0_sum;
	assign factor1[10] = s2_c9_fa0_carry;
	assign factor2[10] = s2_c10_fa0_sum;
	assign factor1[11] = s2_c10_fa0_carry;
	assign factor2[11] = s2_c11_fa0_sum;
	assign factor1[12] = s2_c11_fa0_carry;
	assign factor2[12] = s2_c12_fa0_sum;
	assign factor1[13] = s2_c12_fa0_carry;
	assign factor2[13] = s2_c13_fa0_sum;
	assign factor1[14] = s2_c13_fa0_carry;
	assign factor2[14] = pp_7_7;
	assign factor1[15] = 1'b0;
	assign factor2[15] = 1'b0;
endmodule
