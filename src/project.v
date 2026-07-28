/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

/*

    .sclk(uio_in[3]),          // SPI clock from uio_in[0]
    .cs(uio_in[0]),            // SPI chip select from uio_in[1]
    .mosi(uio_in[1]),          // SPI master out slave in from uio_in[2]
    .clk(clk),                 // System clock
    .rst_n(rst_n),             // Active low reset
    .miso(uio_out[2]),         // SPI master in slave out to uio_out[0]

*/

module tt_um_140oo041_fpu130 (
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
    .fpu_pulse(fpu_pulse),
    .input_data_ready(input_data_ready),
    .result_ready(result_ready),


    .next_state(next_state),
    .state(state)
  );

/*
  Counter to count # of bytes received on SPI.
*/

  wire[2:0] byte_count;
  reg byte_ready_d;
  wire byte_ready_rising_edge = byte_ready & ~byte_ready_d;
  wire byte_ready_falling_edge = ~byte_ready & byte_ready_d;
  wire byte_ready_second_edge = byte_ready & byte_ready_d;

  always @(posedge clk) begin
    byte_ready_d <= byte_ready;
  end

  three_bit_counter byte_counter_inst (
    .clk(clk),
    .count_clk(byte_ready_rising_edge),
    .rst_n(rst_n & (state != 3'b010)), // Reset counter when not in RECEIVE or PROCESS state
    .count(byte_count)
  );

/*
  Assigning data based on number of states.
*/


  reg[7:0] opcode;
  reg[15:0] op1;
  reg[15:0] op2;
  wire arity = opcode[3]; // 0 for unary, 1 for binary
  wire[2:0] tag = opcode[2:0]; // 3-bit tag for operation type
  reg input_data_ready;

  always @(negedge clk) begin
    if(!rst_n) begin
      opcode <= 8'b0;
      op1 <= 16'b0;
      op2 <= 16'b0;
      input_data_ready <= 1'b0;
    end else if(byte_ready_second_edge) begin
      if((arity == 1'b0 && byte_count == 3'b100) ||(arity == 1'b1 && byte_count == 3'b110)) begin input_data_ready <= 1'b1; end
      else begin input_data_ready <= 1'b0; 
      case(byte_count)
        3'b001: begin opcode <= received_data; end
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
  end

/*
  SPI module instantiation
*/


  wire cs_sync;
  wire[7:0] received_data;
  wire byte_ready;
  wire spi_error;
  wire data_transmitted;

  SPI spi_inst (


  // operating signals
    .clk(clk),                 // System clock
    .rst_n(rst_n),             // Active low reset

  //SPI signals
    .sclk(uio_in[3]),          // SPI clock from uio_in[0]
    .cs(uio_in[0]),            // SPI chip select from uio_in[1]
    .mosi(uio_in[1]),          // SPI master out slave in from uio_in[2]
    .miso(uio_out[2]),         // SPI master in slave out to uio_out[0]

  //FSM signals
    .cs_sync_t(cs_sync),
    .transmitted(data_transmitted),
    .error(spi_error),       // SPI error signal
    .frame_complete(fpu_pulse), // Frame complete signal

    .received_data(received_data),    // Received data output
    .byte_ready(byte_ready),    // Byte ready signal


    .write_data(result),
    .transmit(result_ready)
  );


/*
  FPU module instantiation
*/


wire[23:0] result = {status, accumulate_register}; // 24-bit result from FPU and status flags
wire [15:0]accumulate_register; // 16-bit result from FPU
// FPU error flags are computed but not surfaced on any pin in this design.
// They are connected to real wires and tied into `_unused` below so the
// linter flags neither a missing pin nor an unused signal.
wire fpu_flag_NAN;
wire fpu_flag_overflow;
wire fpu_flag_underflow;

reg fpu_enable_d;
wire fpu_enable = input_data_ready; // Enable FPU when input data is ready and in PROCESS state

always @(posedge clk) begin
  fpu_enable_d <= fpu_enable;
end

wire fpu_pulse =  fpu_enable && !fpu_enable_d;

fpu_system fpu_system_inst (
    .clk(clk),
    .reset_n(rst_n),
    .data_ready(fpu_pulse), // Only enable FPU when in PROCESS state
    .A(op1),
    .B(op2),
    .op(opcode[7:5]),
    .acc(opcode[4]),
    .accumulate_register(accumulate_register),
    .result_ready(result_ready),
    .flag_NAN(fpu_flag_NAN),
    .flag_overflow(fpu_flag_overflow),
    .flag_underflow(fpu_flag_underflow));
  wire result_ready;
  wire[7:0] status = {tag, spi_error, 1'b1, fpu_flag_underflow,fpu_flag_overflow,fpu_flag_NAN}; // 8-bit status with error and data_ready flags



    // List all unused inputs to prevent warnings
  wire _unused = &{ena,ui_in[7:0], 1'b0,uio_in[7:4]};

    // All output pins must be assigned. If not used, assign to 0.
  assign uo_out  = 0;
  assign uio_out[7:3] = 0;
  assign uio_out[1:0] = 0; //uio_out[2] is used for MISO in SPI, so we don't assign it to 0.
  assign uio_oe  = 4;



endmodule