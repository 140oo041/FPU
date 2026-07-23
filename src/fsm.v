module fsm (
  
  //operating signals
  input wire clk,
  input wire rst_n,


  input wire cs_sync, // idle -> SPI

  input wire input_data_ready, //SPI -> process 
  input wire fpu_pulse, //SPI -> process

  input wire result_ready, //process -> idle

  output reg [2:0] next_state,
  output reg [2:0] state
);

localparam IDLE = 3'b000;
localparam SPI = 3'b001;
localparam PROCESS = 3'b010;

always @(*) begin
  case(state)

    IDLE: begin
      if(~cs_sync) begin
        next_state = SPI;
      end else begin
        next_state = IDLE;
      end
    end

    SPI: begin
      if(fpu_pulse) begin
          next_state = PROCESS;
        end
      else begin
        next_state = SPI;
      end
    end

    PROCESS: begin
      if(result_ready) begin
        next_state = IDLE;
      end else begin
        next_state = PROCESS;
      end
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