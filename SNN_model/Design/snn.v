`timescale 1ns / 1ps
//  Architecture:
//    Input  : 16x16, 2 channels  -> 512 bits per timestep
//    Conv1  : 8 filters, 3x3, pad=1  -> 8x16x16 = 2048 bits
//    Pool1  : 2x2                    -> 8x8x8   =  512 bits
//    Conv2  : 16 filters, 3x3, pad=1 -> 16x8x8  = 1024 bits
//    Pool2  : 2x2                    -> 16x4x4  =  256 bits
//    FC1    : 256->32  (BRAM weights)
//    FC2    : 32->4    (BRAM weights)
//    Output : 4-bit spike bus, accumulated over TIMESTEPS


module snn_top #(
    parameter BETA       = 128,
    parameter THRESHOLD  = 16'd128,
    parameter IN_CH      = 2,
    parameter IN_H       = 16,
    parameter IN_W       = 16,
    parameter CONV1_FILT = 8,
    parameter CONV2_FILT = 16,

    localparam IN_SIZE   = IN_CH * IN_H * IN_W,             // 512
    localparam CONV1_OUT = CONV1_FILT * IN_H * IN_W,        // 2048
    localparam POOL1_H   = IN_H / 2,
    localparam POOL1_W   = IN_W / 2,
    localparam POOL1_OUT = CONV1_FILT * POOL1_H * POOL1_W,  // 512
    localparam CONV2_OUT = CONV2_FILT * POOL1_H * POOL1_W,  // 1024
    localparam POOL2_H   = POOL1_H / 2,
    localparam POOL2_W   = POOL1_W / 2,
    localparam POOL2_OUT = CONV2_FILT * POOL2_H * POOL2_W,  // 256
    localparam FC1_OUT   = 32,
    localparam FC2_OUT   = 4,

    localparam CONV1_W_SZ = CONV1_FILT * IN_CH * 3 * 3 * 16,      // 2304
    localparam CONV2_W_SZ = CONV2_FILT * CONV1_FILT * 3 * 3 * 16  // 18432
) (
    input wire clk,
    input wire rst,

    input wire [IN_SIZE-1:0] in_spikes,
    input wire               in_valid,   // assert for 1 cycle per frame

    input wire [CONV1_W_SZ-1:0] conv1_weights,
    input wire [CONV2_W_SZ-1:0] conv2_weights,

    output wire [  FC2_OUT-1:0] out_spikes,
    output wire [FC2_OUT*8-1:0] spike_count
);

  // ── Internal spike buses ──────────────────────────────────────────────────────
  reg  [  IN_SIZE-1:0] in_reg;
  wire [CONV1_OUT-1:0] s_conv1;
  wire [POOL1_OUT-1:0] s_pool1;
  wire [CONV2_OUT-1:0] s_conv2;
  wire [POOL2_OUT-1:0] s_pool2;
  wire [  FC1_OUT-1:0] s_fc1_raw;
  wire [  FC2_OUT-1:0] s_fc2;

  reg  [          1:0] fc1_start_cnt;
  reg                  fc1_start;

  always @(posedge clk) begin
    if (rst) begin
      in_reg        <= {IN_SIZE{1'b0}};
      fc1_start_cnt <= 2'd0;
      fc1_start     <= 1'b0;
    end else begin
      fc1_start <= 1'b0;  // default: no pulse

      if (in_valid) begin
        in_reg        <= in_spikes;
        fc1_start_cnt <= 2'd3;  // count down 3 cycles
      end else if (fc1_start_cnt > 0) begin
        fc1_start_cnt <= fc1_start_cnt - 1;
        if (fc1_start_cnt == 2'd1) fc1_start <= 1'b1;  // pulse on last count
      end
    end
  end

  wire fc1_done;
  reg  fc2_start;

  reg  fc1_done_reg;
  always @(posedge clk) begin
    if (rst) begin
      fc2_start    <= 1'b0;
      fc1_done_reg <= 1'b1;
    end else begin
      fc1_done_reg <= fc1_done;
      fc2_start    <= fc1_done && !fc1_done_reg;  // rising edge only
    end
  end

  // ── Stage 1: Conv1 ────────────────────────────────────────────────────────────
  conv_layer #(
      .beta        (BETA),
      .threshold   (THRESHOLD),
      .in_channels (IN_CH),
      .kernel      (3),
      .out_channels(CONV1_FILT),
      .padding     (1),
      .img_size    (IN_H)
  ) u_conv1 (
      .clk      (clk),
      .reset    (rst),
      .in_data  (in_reg),
      .weight_in(conv1_weights),
      .spike_out(s_conv1)
  );

  // ── Stage 2: Pool1 ────────────────────────────────────────────────────────────
  max_pool #(
      .CHANNEL  (CONV1_FILT),
      .IMG_SIZE (IN_H),
      .POOL_SIZE(2)
  ) u_pool1 (
      .clk      (clk),
      .reset    (rst),
      .in_data  (s_conv1),
      .spike_out(s_pool1)
  );

  // ── Stage 3: Conv2 ────────────────────────────────────────────────────────────
  conv_layer #(
      .beta        (BETA),
      .threshold   (THRESHOLD),
      .in_channels (CONV1_FILT),
      .kernel      (3),
      .out_channels(CONV2_FILT),
      .padding     (1),
      .img_size    (POOL1_H)
  ) u_conv2 (
      .clk      (clk),
      .reset    (rst),
      .in_data  (s_pool1),
      .weight_in(conv2_weights),
      .spike_out(s_conv2)
  );

  // ── Stage 4: Pool2 ────────────────────────────────────────────────────────────
  max_pool #(
      .CHANNEL  (CONV2_FILT),
      .IMG_SIZE (POOL1_H),
      .POOL_SIZE(2)
  ) u_pool2 (
      .clk      (clk),
      .reset    (rst),
      .in_data  (s_conv2),
      .spike_out(s_pool2)
  );

  // ── Stage 5: FC1 (256->32) ────────────────────────────────────────────────────
  localparam FC1_BRAM_D = FC1_OUT * POOL2_OUT;  // 8192

  (* ram_style = "block" *)reg  [15:0] fc1_bram       [0:FC1_BRAM_D-1];
  wire [31:0] fc1_bram_addr;
  wire        fc1_bram_en;
  reg  [15:0] fc1_bram_rdata;

  always @(posedge clk) if (fc1_bram_en) fc1_bram_rdata <= fc1_bram[fc1_bram_addr[12:0]];

  ann_layers #(
      .INPUT_SIZE (POOL2_OUT),
      .OUTPUT_SIZE(FC1_OUT),
      .beta       (BETA),
      .threshold  (THRESHOLD)
  ) u_fc1 (
      .clk       (clk),
      .reset     (rst),
      .start     (fc1_start),       // restart after each timestep
      .in_data   (s_pool2),         // direct from pool2, valid when fc1_start fires
      .bram_addr (fc1_bram_addr),
      .bram_en   (fc1_bram_en),
      .bram_rdata(fc1_bram_rdata),
      .layer_done(fc1_done),        // pulses when all 32 FC1 neurons computed
      .spike_out (s_fc1_raw)
  );

  // ── Stage 6: FC2 (32->4) ──────────────────────────────────────────────────────
  localparam FC2_BRAM_D = FC2_OUT * FC1_OUT;  // 128

  (* ram_style = "block" *)reg  [15:0] fc2_bram       [0:FC2_BRAM_D-1];
  wire [31:0] fc2_bram_addr;
  wire        fc2_bram_en;
  reg  [15:0] fc2_bram_rdata;
  wire        fc2_done;

  always @(posedge clk) if (fc2_bram_en) fc2_bram_rdata <= fc2_bram[fc2_bram_addr[6:0]];

  ann_layers #(
      .INPUT_SIZE (FC1_OUT),
      .OUTPUT_SIZE(FC2_OUT),
      .beta       (BETA),
      .threshold  (THRESHOLD)
  ) u_fc2 (
      .clk       (clk),
      .reset     (rst),
      .start     (fc2_start),       // restart triggered by fc1_done
      .in_data   (s_fc1_raw),       // FC1 spike_out held stable until next start
      .bram_addr (fc2_bram_addr),
      .bram_en   (fc2_bram_en),
      .bram_rdata(fc2_bram_rdata),
      .layer_done(fc2_done),        // pulses when all 4 FC2 neurons computed
      .spike_out (s_fc2)
  );

  // ── Output & accumulator ──────────────────────────────────────────────────────
  // Sample s_fc2 exactly once per timestep: when fc2_done pulses.
  // This avoids counting the same spike multiple cycles.
  assign out_spikes = s_fc2;

  reg [7:0] internal_counts[0:FC2_OUT-1];
  integer ci;

  // NEW: Edge detection register to catch the exact moment FC2 finishes
  reg fc2_done_reg;
  always @(posedge clk) begin
    if (rst) fc2_done_reg <= 1'b1;
    else fc2_done_reg <= fc2_done;
  end

  // Create a 1-cycle strobe pulse when fc2_done goes from 0 -> 1
  wire fc2_done_pulse = fc2_done && !fc2_done_reg;
  reg fc2_done_pulse_d1, fc2_done_pulse_d2;
  always @(posedge clk) begin
    if (rst) begin
      fc2_done_pulse_d1 <= 1'b0;
      fc2_done_pulse_d2 <= 1'b0;
    end else begin
      fc2_done_pulse_d1 <= fc2_done_pulse;
      fc2_done_pulse_d2 <= fc2_done_pulse_d1;
    end
  end
  always @(posedge clk) begin
    if (rst) begin
      for (ci = 0; ci < FC2_OUT; ci = ci + 1) internal_counts[ci] <= 8'd0;
    end else if (fc2_done_pulse_d2) begin  // ← was fc2_done_pulse
      for (ci = 0; ci < FC2_OUT; ci = ci + 1)
      if (s_fc2[ci]) internal_counts[ci] <= internal_counts[ci] + 8'd1;
    end
  end

  genvar g;
  generate
    for (g = 0; g < FC2_OUT; g = g + 1) begin : pack_output
      assign spike_count[g*8+:8] = internal_counts[g];
    end
  endgenerate

endmodule
