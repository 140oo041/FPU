/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

/*
  FSM to manage the states of the SPI communication.
*/

  wire [2:0] next_state;
  wire [2:0] state;

  fsm fsm_inst (
    .clk(clk),
    .rst_n(rst_n),
    .cs_sync(cs_sync),
    .data_ready(data_ready),
    .error(spi_error),
    .next_state(next_state),
    .state(state)
  );

/*
  Counter to count # of bytes received on SPI.
*/

  wire[2:0] byte_count;
  reg data_ready_d;
  wire data_ready_rising_edge = data_ready & ~data_ready_d;
  wire data_ready_falling_edge = ~data_ready & data_ready_d;
  wire data_ready_second_edge = data_ready & data_ready_d;

  always @(posedge clk) begin
    data_ready_d <= data_ready;
  end

  three_bit_counter byte_counter_inst (
    .clk(clk),
    .count_clk(data_ready_rising_edge),
    .rst_n(rst_n),
    .count(byte_count)
  );

/*
  Assigning data based on number of states.
*/


  reg[7:0] opcode;
  reg[15:0] op1;
  reg[15:0] op2;

  always @(negedge clk) begin
    if(!rst_n) begin
      opcode <= 8'b0;
      op1 <= 16'b0;
      op2 <= 16'b0;
    end else if(data_ready_second_edge) begin
      case(byte_count)
        3'b001: opcode <= received_data;
        3'b010: op1[15:8] <= received_data;
        3'b011: op1[7:0] <= received_data;
        3'b100: op2[15:8] <= received_data;
        3'b101: op2[7:0] <= received_data;
        default: begin
          opcode <= opcode;
          op1 <= op1;
          op2 <= op2;
        end
      endcase
    end
  end

/*
  SPI module instantiation
*/


  wire cs_sync;
  wire[7:0] received_data;
  wire data_ready;
  wire spi_error;

  SPI spi_inst (
    .sclk(uio_in[3]),          // SPI clock from uio_in[0]
    .cs(uio_in[0]),            // SPI chip select from uio_in[1]
    .mosi(uio_in[1]),          // SPI master out slave in from uio_in[2]
    .clk(clk),                 // System clock
    .rst_n(rst_n),             // Active low reset
    .miso(uio_out[2]),         // SPI master in slave out to uio_out[0]
    .received_data(received_data),    // Received data output
    .data_ready(data_ready),    // Data ready signal to uio_oe[0]
    .error(spi_error),       // SPI error signal
    .cs_sync_t(cs_sync),
    .state(state),
    .next_state(next_state)
  );


/*
  FPU module instantiation
*/

wire[15:0] accumulate_register;

fpu_system fpu_system_inst (
    .clk(clk),
    .reset_n(rst_n),
    .data_ready(data_ready),
    .A(op1),
    .B(op2),
    .op(opcode[7:5]),
    .acc(opcode[4]),
    .accumulate_register(accumulate_register),
    .result_ready(uio_oe[3]));



    // List all unused inputs to prevent warnings
  wire _unused = &{ena,ui_in[7:0], 1'b0,uio_in[7:4]};

    // All output pins must be assigned. If not used, assign to 0.
  assign uo_out  = 0;
  assign uio_out[7:3] = 0;
  assign uio_out[1:0] = 0; //uio_out[2] is used for MISO in SPI, so we don't assign it to 0.
  assign uio_oe  = 4;

endmodule

module SPI (
  input wire sclk,
  input wire cs,
  input wire mosi,
  input wire clk,
  input wire rst_n,
  input wire [2:0] next_state,
  input wire [2:0] state,
  output wire miso,
  output wire [7:0] received_data,
  output wire data_ready,
  output wire error,
  output wire cs_sync_t

);

localparam IDLE = 3'b000;
localparam RECEIVE = 3'b001;
localparam PROCESS = 3'b010;
localparam WRITEBACK = 3'b011;

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

  always @(posedge clk) begin
    FF3 <= sclk_sync;
    if (!rst_n) begin
      sclk_rising_edge <= 1'b0;
    end else begin
      sclk_rising_edge <= sclk_sync & ~FF3;
    end
  end

  // SPI logic here

  reg [7:0] shift_reg;
  wire [3:0] bit_count;

  //4 bit counter

  byte_counter bit_counter_inst (
    .clk(clk),
    .count_clk(sclk_rising_edge),
    .rst_n(rst_n),
    .count(bit_count)
  );

  always @(posedge clk) begin
    if (!rst_n) begin
      shift_reg <= 8'b0;
    end else if (cs_sync & sclk_rising_edge && state == RECEIVE) begin
      shift_reg <= {shift_reg[6:0], mosi_sync};
    end else if (state == IDLE) begin
      shift_reg <= 8'b0;
    end else if (state == PROCESS) begin
      shift_reg <= 8'b0;
    end else if (state == WRITEBACK) begin
      shift_reg <= 8'b0;
    end
  end


  assign  received_data = shift_reg;
  assign  data_ready = (bit_count == 4'b1000) && cs_sync;

  //CRC calculation
  wire [7:0] crc_out;

  CRC_Eight crc_inst (
    .mosi(mosi_sync),
    .rst_n(rst_n),
    .clk(clk),
    .sync_clk(sclk_rising_edge),
    .crc(crc_out)
  );

  assign error = ((crc_out^8'hFF) != 8'b00000000) && data_ready;






endmodule



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

module fsm (
  input wire clk,
  input wire rst_n,
  input wire cs_sync,
  input wire data_ready,
  input wire error,
  output reg [2:0] next_state,
  output reg [2:0] state
);

localparam IDLE = 3'b000;
localparam RECEIVE = 3'b001;
localparam PROCESS = 3'b010;
localparam WRITEBACK = 3'b011;

always @(*) begin
  case(state)
    IDLE: begin
      if(cs_sync) begin
        next_state = RECEIVE;
      end else begin
        next_state = IDLE;
      end
    end
    RECEIVE: begin
      if(~cs_sync) begin
          next_state = PROCESS;
        end
      else begin
        next_state = RECEIVE;
      end
    end
    PROCESS: begin
      next_state = IDLE;
    end
    default: begin
      next_state = IDLE;
    end
  endcase
end

always @(posedge clk) begin
  if(!rst_n) begin
    state <= IDLE;
  end else begin
    state <= next_state;
  end
end

endmodule

module fpu_system(
    input wire clk,
    input wire reset_n,
    input wire data_ready,
    input wire[15:0] A, B, //I/O Registers
    input wire[2:0] op, //I/O Registers
    input wire acc, //I/O Registers
    output reg[15:0] accumulate_register, //Register in FPU_System 
    output reg result_ready
    );

    wire[15:0] datapath_result;
    wire accumulate_register_enable;
    wire[15:0] input_a;
        assign input_a = acc ? accumulate_register : A;

    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            accumulate_register <= 16'b0;
            result_ready <= 1'b0;
        end

        else if(data_ready && accumulate_register_enable) begin
            accumulate_register <= datapath_result;
            result_ready <= 1'b1;
        end

        else begin
            result_ready <= 1'b0;
        end
    end

    fpu_core fpuCore(
        .A(input_a),
        .B(B),
        .op(op),
        .result(datapath_result),
        .accumulate_enable(accumulate_register_enable)
    );


endmodule

module fpu_core(
  input wire[15:0] A,
  input wire[15:0] B,
  input wire[2:0] op,
  output wire[15:0] result,
  output wire accumulate_enable
);

endmodule