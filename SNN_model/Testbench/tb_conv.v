`timescale 1ns / 1ps


module tb_conv;
  parameter in_channels = 1;
  parameter out_channels = 4;
  parameter kernel = 3;
  parameter img_size = 4;
  parameter padding = 1;
  parameter beta = 112;
  parameter threshold = 16'd255;

  localparam INPUT_SIZE = in_channels * img_size * img_size;  
  localparam OUTPUT_SIZE = out_channels * (img_size ) * (img_size );  
  localparam WEIGHT_SIZE = out_channels * kernel * kernel * in_channels * 16;  

  reg clk_tc1 = 0;
  reg reset_tc1;
  reg [INPUT_SIZE-1:0] in_data_tc1;
  reg [WEIGHT_SIZE-1:0] weight_in_tc1;
  wire [OUTPUT_SIZE-1:0] spike_out_tc1;

  conv_layer #(
      .in_channels(in_channels),
      .out_channels(out_channels),
      .kernel(kernel),
      .img_size(img_size),
      .padding(padding),
      .beta(beta),
      .threshold(threshold)
  ) uut_tc1 (
      .clk(clk_tc1),
      .reset(reset_tc1),
      .in_data(in_data_tc1),
      .weight_in(weight_in_tc1),
      .spike_out(spike_out_tc1)
  );






  always #5 clk_tc1 = ~clk_tc1;




  initial begin
 
    $display("========== TEST CASE 1: 3x3 kernel, padding=1 ==========");
    reset_tc1 = 1'b1;
    in_data_tc1 = {INPUT_SIZE{1'b0}};
    weight_in_tc1 = {WEIGHT_SIZE{1'b0}};
    repeat (5) @(posedge clk_tc1);

     reset_tc1 = 1'b0;
      repeat (2) @(posedge clk_tc1);
  in_data_tc1   = 64'b10101010_01010101_10101010_01010101_10101010_01010101_10101010_01010101;
//   weight_in_tc1 = {1'b0,{WEIGHT_SIZE-1{1'b1}}};  
    weight_in_tc1 = { {9{16'h0ffA}}, {9{16'h0100}}, {9{16'h00ff}}, {9{16'h0ff1}} };
   
 
    repeat (250) @(posedge clk_tc1);
    $finish;
  end

endmodule
