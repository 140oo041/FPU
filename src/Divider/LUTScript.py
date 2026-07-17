
def LUTScript():
    print("module dividerLUT(")
    print("\tinput wire[6:0] index,")
    print("\toutput reg[7:0] reciprocal")
    print("\t);")
    print()

    print("\talways @(*) begin")
    print("\t\tcase(index)")

    for i in range(128):
        val = 1.0 / (1.0 + (i / 128.0))
        int_val = int(round(val * 256))
        if int_val > 255:
            int_val = 255
        print(f"\t\t\t7'd{i}: reciprocal = 8'b{int_val:08b};")

    print("\t\t\tdefault: reciprocal = 8'b00000000;")
    print("\t\tendcase")
    print("\tend")
    print("endmodule")


LUTScript()