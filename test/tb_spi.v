`default_nettype none
`timescale 1ns / 1ps

// Passive wrapper for the SPI block so cocotb (test_spi.py) can drive it
// directly. Mirrors the style of tb.v but instantiates SPI on its own.
module tb_spi ();

  initial begin
    $dumpfile("tb_spi.fst");
    $dumpvars(0, tb_spi);
    #1;
  end

  reg         clk;
  reg         rst_n;
  reg         sclk;
  reg         cs;
  reg         mosi;
  wire        miso;
  reg  [2:0]  state;
  wire        cs_sync_t;
  wire        transmitted;
  wire        error;
  reg  [23:0] write_data;
  reg         transmit;
  wire [7:0]  received_data;
  wire        byte_ready;

  SPI dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .sclk          (sclk),
    .cs            (cs),
    .mosi          (mosi),
    .miso          (miso),
    .state         (state),
    .cs_sync_t     (cs_sync_t),
    .transmitted   (transmitted),
    .error         (error),
    .write_data    (write_data),
    .transmit      (transmit),
    .received_data (received_data),
    .byte_ready    (byte_ready)
  );

endmodule
