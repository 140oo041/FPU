module SPI (

// operating signals
  input wire clk,
  input wire rst_n,

//SPI signals
  input wire sclk,
  input wire cs,
  input wire mosi,
  output reg miso,

// FSM signals
  input wire frame_complete,
  output wire cs_sync_t,
  output wire transmitted,
  output reg error,


// Writeback signals
  input wire [23:0] write_data,
  input wire transmit,

// Receive signals
  output wire [7:0] received_data,
  output wire byte_ready




);


assign cs_sync_t = cs_sync;

//synchronizer for mosi and miso
  wire mosi_sync;

  synchronizer mosi_sync_inst (
    .clk(clk),
    .rst_n(rst_n),
    .async_in(mosi),
    .sync_out(mosi_sync)
  );

  wire cs_sync;
  synchronizer #(1'b1) cs_sync_inst (
    .clk(clk),
    .rst_n(rst_n),
    .async_in(cs),
    .sync_out(cs_sync)
  );


  //Edge detection for sclk
  reg sclk_rising_edge;
  wire sclk_sync;
  reg FF3;

  synchronizer sclk_sync_inst (
    .clk(clk),
    .rst_n(rst_n),
    .async_in(sclk),
    .sync_out(sclk_sync)
  );


  //sclk rising edge detection 
  always @(posedge clk) begin
    FF3 <= sclk_sync;
    if (!rst_n) begin
      sclk_rising_edge <= 1'b0;
    end else begin
      sclk_rising_edge <= sclk_sync & ~FF3;
    end
  end

  reg cs_rising_edge;
  reg FF4;
  //cs rising edge detection 
  always @(posedge clk) begin
    FF4 <= ~cs_sync;
    if (!rst_n) begin
      cs_rising_edge <= 1'b0;
    end else begin
      cs_rising_edge <= ~cs_sync & ~FF4;
    end
  end

  // SPI logic here

  reg [7:0] shift_in_reg;
  wire [3:0] bit_count_in_byte;

  //4 bit counter

  byte_counter bit_counter_receive_inst (
    .clk(clk),
    .count_clk(~cs_sync & sclk_rising_edge),
    .rst_n(rst_n & ~frame_complete),
    .count(bit_count_in_byte)
  );

  wire [23:0] write_data_inverted;
  genvar i;
  generate
    for (i = 0; i < 24; i = i + 1) begin
      assign write_data_inverted[i] = write_data[23 - i];
    end
  endgenerate

  always@(posedge clk) begin
    if(!rst_n) begin
      shift_in_reg <= 8'b0;
      miso <= 1'b0;
    end 
    
    else if (sclk_rising_edge & ~cs_sync)begin
      shift_in_reg <= {shift_in_reg[6:0], mosi_sync};
      miso <= write_data_inverted[out_bit_count];
    end

    else if(cs_rising_edge) begin
      miso <= write_data_inverted[0]; end
  end

  assign transmitted = (out_bit_count == 5'd23) && ~cs_sync && sclk_rising_edge;

  
  wire[4:0] out_bit_count;

  twenty_four_counter bit_counter_writeback_inst (
    .clk(clk),
    .count_clk(~cs_sync & sclk_rising_edge),
    .rst_n(rst_n & ~frame_complete),
    .count(out_bit_count)
  );


  assign  received_data = shift_in_reg;
  assign  byte_ready = (bit_count_in_byte == 4'b1000) && ~cs_sync;

  //CRC calculation
  wire [7:0] crc_out;

  CRC_Eight crc_inst (
    .mosi(mosi_sync),
    .rst_n(rst_n & ~frame_complete),
    .clk(clk),
    .sync_clk(sclk_rising_edge),
    .crc(crc_out)
  );


  always @(posedge clk) begin
    if(!rst_n) begin
      error <= 1'b0;
    end else if(frame_complete) begin
      error <= (crc_out != 8'h42);
    end
  end
endmodule