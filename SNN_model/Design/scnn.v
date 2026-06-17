module conv_layer #(
    parameter beta = 112,
    parameter threshold = 16'd255,
    parameter in_channels = 2,
    parameter kernel = 3,
    parameter out_channels = 16,
    parameter padding = 1,
    parameter img_size = 34,
    localparam INPUT_SIZE = in_channels * img_size * img_size,  // 2312 bits
    localparam OUTPUT_SIZE = out_channels * (img_size) * (img_size),                // 18496 bits
    localparam WEIGHT_SIZE = out_channels * in_channels * kernel * kernel * 16, // 4608 bits
    localparam channel_cnt = in_channels * kernel * kernel * 16
) (
    input wire clk,
    input wire reset,
    //shape is 2*34*34
    input wire [INPUT_SIZE-1:0] in_data,
    input wire [WEIGHT_SIZE-1:0] weight_in,
    output reg [OUTPUT_SIZE-1:0] spike_out
);

  reg [16:0] V_mem[0:OUTPUT_SIZE-1]; //memory to store the membrane potential for each output pixel (10 bits for each pixel)
  reg [10:0] row, col;
  reg [4:0] channel;
  reg [15:0] weights[0:kernel*kernel*in_channels-1];  // 18 weights of 16 bits each (16*18=288)
  reg [kernel*kernel*in_channels-1:0] total_pix;    
  reg [16:0] out_pixel_addr;

  //pipeline stage 1 
  reg [kernel*kernel*in_channels-1:0] pix_1;
  reg [15:0] weights_1[0:kernel*kernel*in_channels-1];
  reg valid_1;
  reg [16:0] out_pixel_addr_1;

  //pipeline stage 2
  reg [16:0] accumulator;
  reg [16:0] out_pixel_addr_2;
  reg valid_2;

  //pipeline stage 3
  reg [16:0] comb_voltage;

  //temp
  integer r, c, ch, pix;
  reg  [16:0] out_pixel;

  integer row_in, col_in;  // input image coordinates

  //extracting pixels for convolution and weights for the current output pixel
  always @(*) begin
    //extracting pixels for convolution
    for (ch = 0; ch < in_channels; ch = ch + 1) begin
      for (r = 0; r < kernel; r = r + 1) begin
        for (c = 0; c < kernel; c = c + 1) begin
          row_in = row + r - padding;
          col_in = col + c - padding;
          if (row_in >= 0 && row_in < img_size && col_in >= 0 && col_in < img_size) begin
            total_pix[(ch*kernel*kernel)+(r*kernel)+(c)] = 
                            in_data[(ch*img_size*img_size)+(row_in*img_size)+col_in];
          end else begin
            total_pix[(ch*kernel*kernel)+(r*kernel)+(c)] = 1'b0;
          end
        end
      end
    end


    for (pix = 0; pix < (kernel * kernel * in_channels); pix = pix + 1) begin
      weights[pix] = weight_in[(channel*channel_cnt)+(pix*16)+:16];
    end

    out_pixel_addr = (channel * img_size * img_size) + (row * img_size) + col;
  end

  //stage 1: load pixels and weights for the current output pixel
  always @(posedge clk) begin
    if (reset) begin        
      pix_1   <= 0;
      valid_1 <= 0;
    end else begin
      pix_1 <= total_pix;
      for (pix = 0; pix < (kernel * kernel * in_channels); pix = pix + 1) begin
        weights_1[pix] <= weights[pix];
      end
      out_pixel_addr_1 <= out_pixel_addr;
      valid_1 <= 1'b1;
    end
  end

  //stage 2: perform convolution and update membrane potential
      always @(*) begin
         accumulator = 17'b0;
        if (valid_1) begin
          for (pix = 0; pix < (kernel * kernel * in_channels); pix = pix + 1) begin
            if (pix_1[pix]) accumulator = accumulator + weights_1[pix];
          end
        end
      end

  always @(posedge clk) begin
    if (reset) begin
      comb_voltage <= 0;
      valid_2 <= 0;
    end else begin
      comb_voltage <= accumulator;
      out_pixel_addr_2 <= out_pixel_addr_1;
      valid_2 <= valid_1;
    end
  end
  
  //stage 3 : compare with threshold, generate spike, and reset membrane potential 
  wire [16:0] final_voltage = ((V_mem[out_pixel_addr_2] * beta)>>8) + (comb_voltage);
  integer i;
  always @(posedge clk) begin
    if (reset) begin
      row <= 0;
      col <= 0;
      channel <= 0;
       spike_out <= {OUTPUT_SIZE{1'b0}}; 
       for (i = 0; i < OUTPUT_SIZE; i = i + 1) V_mem[i] <= 17'b0;
    end else begin
      if (valid_2) begin
        if (final_voltage > (threshold)) begin
          spike_out[out_pixel_addr_2] <= 1'b1;
          V_mem[out_pixel_addr_2] <= 9'b0;  //reset the membrane potential after spike
        end else begin
          spike_out[out_pixel_addr_2] <= 1'b0;
          V_mem[out_pixel_addr_2] <= final_voltage;  //update the membrane potential
        end
      end

      if (col < img_size - 1) col <= col + 1;
      else begin
        col <= 0;
        if (row < img_size - 1) row <= row + 1;
        else begin
          row <= 0;
          if (channel < out_channels - 1) begin
            channel <= channel + 1;
          end else channel <= 0;
        end
      end
    end
  end
endmodule
