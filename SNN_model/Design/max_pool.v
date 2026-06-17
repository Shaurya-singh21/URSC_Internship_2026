    module max_pool #(
        parameter CHANNEL     = 16,
        parameter IMG_SIZE    = 34,
        parameter POOL_SIZE   = 2,
        parameter INPUT_SIZE  = CHANNEL * IMG_SIZE * IMG_SIZE,                             // 18496 bits
        parameter OUTPUT_SIZE = CHANNEL * (IMG_SIZE / POOL_SIZE) * (IMG_SIZE / POOL_SIZE)  // 4352 bits
    ) (
        input wire clk,
        input wire reset,
        //shape is 16*34*34
        input wire [INPUT_SIZE-1:0] in_data,
        output reg [OUTPUT_SIZE-1:0] spike_out
    );
      reg [$clog2(IMG_SIZE):0] row;
      reg [$clog2(IMG_SIZE):0] col;
      reg [$clog2(CHANNEL):0] channel;
      reg [3:0] pixel;
      reg valid;
      reg [15:0] out_pixel_addr;
      wire [31:0] out_sheet_size = (IMG_SIZE / POOL_SIZE) * (IMG_SIZE / POOL_SIZE);
      wire [31:0] in_sheet_size = IMG_SIZE * IMG_SIZE;
    
      always @(*) begin
        pixel[0]= in_data[(channel*in_sheet_size)+(row*IMG_SIZE)+col];
        pixel[1] = in_data[(channel*in_sheet_size)+(row*IMG_SIZE)+col+1'b1];
        pixel[2] = in_data[(channel*in_sheet_size)+((row+1'b1)*IMG_SIZE)+col];
        pixel[3] = in_data[(channel*in_sheet_size)+((row+1'b1)*IMG_SIZE)+col+1'b1];
        out_pixel_addr = (channel * out_sheet_size) + ((row/POOL_SIZE) * (IMG_SIZE / POOL_SIZE)) + (col / POOL_SIZE);
      end
    
      reg [ 3:0] pixel_stage_1;
      reg [15:0] out_pixel_addr_1;
      always @(posedge clk) begin
        if (reset) begin
          pixel_stage_1 <= 4'b0;
          valid <= 1'b0;
        end else begin
          pixel_stage_1 <= pixel;
          out_pixel_addr_1 <= out_pixel_addr;
          valid <= 1'b1;  // 
        end
      end
      
      always @(posedge clk) begin
        if (reset) begin
          spike_out <= {OUTPUT_SIZE{1'b0}};
          row <= 0;
          col <= 0;
          channel <= 0;
        end else begin
          if (valid) spike_out[out_pixel_addr_1] <= |pixel_stage_1;
          if (col < (IMG_SIZE - (IMG_SIZE % POOL_SIZE) - POOL_SIZE + 1)) begin
            col <= col + POOL_SIZE;  // Move right by POOL_SIZE
          end else begin
            col <= 0;
            if (row < (IMG_SIZE - (IMG_SIZE % POOL_SIZE) - POOL_SIZE + 1)) begin
              row <= row + POOL_SIZE;  // Move down
            end else begin
              row <= 0;  // Reset to top row
              if (channel < (CHANNEL - 1)) begin
                channel <= channel + 1;  // Move to next sheet
              end else begin
                // Everything is done!
                channel <= 1'b0;
              end
            end
          end
        end
      end
    endmodule
