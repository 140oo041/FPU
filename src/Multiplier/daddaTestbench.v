module daddaTestBench();
  reg[7:0] a, b;
  wire[15:0] factor1, factor2;

  integer i, j;

  daddaMultiplier dut(.a(a), .b(b), .factor1(factor1), .factor2(factor2));

  initial begin
    for(i = 0; i < 256; i = i + 1) begin
      for(j = 0; j < 256; j = j + 1) begin
        a = i;
        b = j;
        #1;
        if(factor1 + factor2 == a * b);
        else $display("FAIL: %0d * %0d = %0d, got %0d", a, b, a * b, factor1 + factor2);
      end
    end

    $display("All tests passed");
    $finish;
  end
endmodule