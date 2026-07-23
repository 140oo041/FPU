module byte_counter (
  input wire clk,
  input wire count_clk,
  input wire rst_n,
  output reg [3:0] count
);

  reg count_clk_d;
  wire count_clk_edge = count_clk & ~count_clk_d;

  always @(posedge clk) begin
    if (!rst_n) begin
      count <= 4'b0000;
      count_clk_d <= 1'b0;
    end else begin
      count_clk_d <= count_clk;
      if(count_clk_edge) begin
        count[0] <= ~count[0];
        count[1] <= count[0] ^ count[1];
        count[2] <= (count[0] & count[1]) ^ count[2];
        count[3] <= (count[0] & count[1] & count[2]);
      end
    end
  end
endmodule

module four_bit_counter (
  input wire clk,
  input wire count_clk,
  input wire rst_n,
  output reg [3:0] count
);

  reg count_clk_d;
  wire count_clk_edge = count_clk & ~count_clk_d;

  always @(posedge clk) begin
    if (!rst_n) begin
      count <= 4'b0000;
      count_clk_d <= 1'b0;
    end else begin
      count_clk_d <= count_clk;
      if(count_clk_edge) begin
        count[0] <= ~count[0];
        count[1] <= count[0] ^ count[1];
        count[2] <= (count[0] & count[1]) ^ count[2];
        count[3] <= (count[0] & count[1] & count[2]) ^ count[3];
      end
    end
  end
endmodule

module three_bit_counter (
  input wire clk,
  input wire count_clk,
  input wire rst_n,
  output reg [2:0] count
);

  reg count_clk_d;
  wire count_clk_edge = count_clk & ~count_clk_d;

  always @(posedge clk) begin
    if (!rst_n) begin
      count <= 3'b000;
      count_clk_d <= 1'b0;
    end else begin
      count_clk_d <= count_clk;
      if(count_clk_edge) begin
        count[0] <= ~count[0];
        count[1] <= count[0] ^ count[1];
        count[2] <= (count[0] & count[1]) ^ count[2];
      end
    end
  end
endmodule

module two_bit_counter (
  input wire clk,
  input wire count_clk,
  input wire rst_n,
  output reg [1:0] count
);

  reg count_clk_d;
  wire count_clk_edge = count_clk & ~count_clk_d;

  always @(posedge clk) begin
    if (!rst_n) begin
      count <= 2'b00;
      count_clk_d <= 1'b0;
    end else begin
      count_clk_d <= count_clk;
      if(count_clk_edge) begin
        count[0] <= ~count[0];
        count[1] <= count[0] ^ count[1];
      end
    end
  end
endmodule

module twenty_four_counter (
  input wire clk,
  input wire count_clk,
  input wire rst_n,
  output reg [4:0] count
);

  reg count_clk_d;
  wire count_clk_edge = count_clk & ~count_clk_d;

  always @(posedge clk) begin
    if (!rst_n) begin
      count <= 5'b00001;
      count_clk_d <= 1'b0;
    end else begin
      count_clk_d <= count_clk;
      if(count_clk_edge) begin
        if(count == 5'd23) begin
          count <= 5'b00001;
        end else begin
          count[0] <= ~count[0];
          count[1] <= count[0] ^ count[1];
          count[2] <= (count[0] & count[1]) ^ count[2];
          count[3] <= (count[0] & count[1] & count[2]) ^ count[3];
          count[4] <= (count[0] & count[1] & count[2] & count[3]) ^ count[4];
        end
      end
    end
  end
endmodule

module synchronizer #(parameter RESET_VAL = 1'b0) (
  input wire clk,
  input wire rst_n,
  input wire async_in,
  output reg sync_out
);

reg FF1;

  always @(posedge clk) begin

    if (!rst_n) begin
      sync_out <= RESET_VAL;
      FF1 <= RESET_VAL;
    end else begin
      FF1 <= async_in;
      sync_out <= FF1;
    end
  end
endmodule

module CRC_Eight (
  input wire mosi,
  input wire rst_n,
  input wire sync_clk,
  input wire clk,
  output reg[7:0] crc
);

  wire fb;
  assign fb = crc[7] ^ mosi;

  always @(posedge clk) begin
    if(!rst_n) begin
        crc <= 8'hFF;
    end else if(sync_clk) begin
        crc[0] <= fb;
        crc[1] <= fb ^ crc[0];
        crc[2] <= fb ^ crc[1];
        crc[3] <= fb ^ crc[2];
        crc[4] <= crc[3];
        crc[5] <= fb ^ crc[4];
        crc[6] <= crc[5];
        crc[7] <= crc[6];
    end
  end
endmodule