`timescale 1ns/1ps

module tb_maxPool;
    parameter CHANNEL   = 1;
    parameter IMG_SIZE  = 4;
    parameter POOL_SIZE = 2;
    parameter INPUT_SIZE  = CHANNEL * IMG_SIZE * IMG_SIZE;                 // 18,496 bits
    parameter OUTPUT_SIZE = CHANNEL * (IMG_SIZE/POOL_SIZE) * (IMG_SIZE/POOL_SIZE); // 4,352 bits
    reg clk = 0;
    reg reset;
    reg  [INPUT_SIZE-1:0]  in_data;
    wire [OUTPUT_SIZE-1:0] spike_out;
    
    integer i;
    max_pool #(
        .CHANNEL(CHANNEL),
        .IMG_SIZE(IMG_SIZE),
        .POOL_SIZE(POOL_SIZE)
    ) uut (
        .clk(clk),
        .reset(reset),
        .in_data(in_data),
        .spike_out(spike_out)
    );

    always #5 clk = ~clk; // Clock generation

    initial begin
        reset = 1'b1;
        in_data = {INPUT_SIZE-1{1'b0}}; // Initialize input data to zero    
        repeat(5) @(posedge clk);   
        for (i = 0; i < 578; i = i + 1) begin
            if (($urandom % 100) < 50) begin
                in_data[i] = 1'b1;
            end else begin
                in_data[i] = 1'b0;
            end
        end
//        in_data = {1'b0,{INPUT_SIZE-1{1'b1}}};
        #100
        reset =0;
        repeat(500) @(posedge clk);
        
        $display("Simulation complete!");
        $finish;
    end
endmodule