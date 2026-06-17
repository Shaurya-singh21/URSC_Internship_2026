`timescale 1ns / 1ps

module tb_ann_layers;

  parameter INPUT_SIZE  = 4;
  parameter OUTPUT_SIZE = 3;
  parameter beta        = 112;
  parameter threshold   = 16'd5;

  reg                    clk = 0;
  reg                    reset;
  reg  [INPUT_SIZE-1:0]  in_data;
  wire [31:0]            bram_addr;
  wire                   bram_en;
  reg  [15:0]            bram_rdata;
  wire                   layer_done;
  wire [OUTPUT_SIZE-1:0] spike_out;

  integer i;

  ann_layers #(
      .INPUT_SIZE(INPUT_SIZE),
      .OUTPUT_SIZE(OUTPUT_SIZE),
      .beta(beta),
      .threshold(threshold)
  ) uut (
      .clk(clk),
      .reset(reset),
      .in_data(in_data),
      .bram_addr(bram_addr),
      .bram_en(bram_en),
      .bram_rdata(bram_rdata),
      .layer_done(layer_done),
      .spike_out(spike_out)
  );

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (reset) begin
      bram_rdata <= 16'b0;
    end else if (bram_en) begin
      bram_rdata <= 16'd4;
    end
  end
  
  
initial begin
    reset   = 1'b1;
    in_data = 4'b1111; // Force all inputs high
    #40;               // Wait 40ns (stably between clock edges)

    reset = 1'b0;      // Release reset smoothly while clock is low
    
    #200;
    $finish;
  end
//  initial begin
//    reset   = 1'b1;
//    in_data = {INPUT_SIZE{1'b0}};
//    repeat (10) @(posedge clk);

//    @(negedge clk);
//    reset = 1'b0;

////    for (i = 0; i < INPUT_SIZE; i = i + 1) begin
////      in_data[i] = (i % 2 == 0) ? 1'b1 : 1'b0;
////    end
//    in_data = 4'b1111;
//    #1400000;
//    $finish;
//  end

endmodule