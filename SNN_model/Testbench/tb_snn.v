`timescale 1ns / 1ps

module tb_snn_top;

    // ─── Simulation Clock & Control ──────────────────────────────────
    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;   

    // ─── Network Parameters (Q8.8 Scaling) ───────────────────────────
    parameter BETA       = 200;
    parameter THRESHOLD  = 16'd255;  // Scaled to exactly 1.0 in Q8.8 space
    parameter IN_CH      = 2;
    parameter IN_H       = 16;
    parameter IN_W       = 16;
    parameter CONV1_FILT = 8;
    parameter CONV2_FILT = 16;
    parameter TIMESTEPS  = 30;

    localparam IN_SIZE    = IN_CH * IN_H * IN_W;          // 512
    localparam CONV1_OUT  = CONV1_FILT * IN_H * IN_W;       // 2048
    localparam POOL1_OUT  = CONV1_FILT * (IN_H/2) * (IN_W/2); // 512
    localparam CONV2_OUT  = CONV2_FILT * (IN_H/2) * (IN_W/2); // 1024
    localparam POOL2_OUT  = CONV2_FILT * (IN_H/4) * (IN_W/4); // 256
    localparam FC1_OUT    = 32;
    localparam FC2_OUT    = 4;

    localparam CONV1_W_SZ = CONV1_FILT * IN_CH * 3 * 3 * 16;     // 2304
    localparam CONV2_W_SZ = CONV2_FILT * CONV1_FILT * 3 * 3 * 16;  // 18432

    // ─── Weight & Data Drivers ───────────────────────────────────────
    reg [15:0] conv1_w_arr [0:143];
    reg [15:0] conv2_w_arr [0:1151];
    reg [CONV1_W_SZ-1:0] conv1_wb;
    reg [CONV2_W_SZ-1:0] conv2_wb;

    reg  [IN_SIZE-1:0] in_spikes;
    reg                in_valid;
    wire [FC2_OUT-1:0] out_spikes;
    wire [FC2_OUT*8-1:0] tb_spike_counts;

    // ─── Unpack Consolidated Counter Output Bus ──────────────────────
    wire [7:0] class_count [0:FC2_OUT-1];
    assign class_count[0] = tb_spike_counts[7:0];
    assign class_count[1] = tb_spike_counts[15:8];
    assign class_count[2] = tb_spike_counts[23:16];
    assign class_count[3] = tb_spike_counts[31:24];

    // ─── Unit Under Test (UUT) Instantiation ─────────────────────────
    snn_top #(
        .BETA(BETA), 
        .THRESHOLD(THRESHOLD)
    ) u_snn (
        .clk(clk),
        .rst(rst),
        .in_spikes(in_spikes),
        .in_valid(in_valid),
        .conv1_weights(conv1_wb),
        .conv2_weights(conv2_wb),
        .out_spikes(out_spikes),
        .spike_count(tb_spike_counts)
    );

    // ─── Capture Output Spikes Synchronously ─────────────────────────
    reg [FC2_OUT-1:0] fc2_out_capture;
    always @(posedge clk) begin
        if (u_snn.fc2_done)
            fc2_out_capture <= out_spikes;
    end

    // ─── Clean Vector Population Population Task ─────────────────────
    function automatic integer popcnt;
        input [2047:0] vec;
        input integer  w;
        integer k; 
        integer s;
        begin 
            s = 0;
            for (k=0; k<w; k=k+1) s = s + vec[k];
            popcnt = s;
        end
    endfunction

    // ─── Hardware Parallel Bus Weight Packing ────────────────────────
    integer pi;
    task pack_weights;
        begin
            for (pi=0; pi<144;  pi=pi+1) conv1_wb[pi*16 +: 16] = conv1_w_arr[pi];
            for (pi=0; pi<1152; pi=pi+1) conv2_wb[pi*16 +: 16] = conv2_w_arr[pi];
        end
    endtask

    // ─── Linear Congruential Generator (15% Spike Frame Driver) ──────
    integer rng_state;
    task gen_frame;
        integer b;
        begin
            for (b=0; b<IN_SIZE; b=b+1) begin
                rng_state = rng_state * 1664525 + 1013904223; 
                in_spikes[b] = (rng_state[30:24] < 7'd19) ? 1'b1 : 1'b0; 
            end
        end
    endtask

    // ─── Main Simulation Control Loop ────────────────────────────────
    integer t, best_cls, best_cnt, i;

    initial begin
        $dumpfile("snn_sim.vcd");
        $dumpvars(0, tb_snn_top);

        // 1. Initialise Block Memories & Parallel Buses
        $readmemh("weights_conv1.hex", conv1_w_arr);
        $readmemh("weights_conv2.hex", conv2_w_arr);
        $readmemh("weights_fc1.hex",   u_snn.fc1_bram);
        $readmemh("weights_fc2.hex",   u_snn.fc2_bram);
        pack_weights;

        // 2. Execution Logging Header Display
        $display("=================================================================");
        $display("  SNN FULL PIPELINE INFERENCE MONITOR  -  %0d TIMESTEPS", TIMESTEPS);
        $display("  Config: Q8.8 Math | Beta: %0d | Threshold: %0d", BETA, THRESHOLD);
        $display("=================================================================");
        $display("%-4s | IN(%%) | C1(%%) | P1(%%) | C2(%%) | P2(%%) | FC1_ACT | FC2_OUT", "STEP");
        $display("-----------------------------------------------------------------");

        // 3. Hardware System Reset Routine
        rng_state = 32'hDEAD_BEEF;
        in_spikes = {IN_SIZE{1'b0}};
        in_valid  = 1'b0;
        repeat(6) @(posedge clk);
        @(negedge clk); rst = 0;
        repeat(4) @(posedge clk);

        // 4. Inference Run Cycle Engine
        for (t=1; t<=TIMESTEPS; t=t+1) begin
            gen_frame;

            @(negedge clk);
            in_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            in_valid = 1'b0;

            // Wait for layer execution pipelines to fully resolve frame states
            repeat(12500) @(posedge clk);

            // Real-Time Layer Diagnostics Tracking Module
           $display("%-4d | %0t ns |  %3d%% |  %3d%% |  %3d%% |  %3d%% |  %3d%% |  %5d/32 |  %04b",
    t, $time/1000,
                (popcnt({1536'b0, in_spikes},      IN_SIZE)   * 100) / IN_SIZE,
                (popcnt({1120'b0, u_snn.s_conv1},   CONV1_OUT) * 100) / CONV1_OUT,
                (popcnt({1536'b0, u_snn.s_pool1},   POOL1_OUT) * 100) / POOL1_OUT,
                (popcnt({1024'b0, u_snn.s_conv2},   CONV2_OUT) * 100) / CONV2_OUT,
                (popcnt({1792'b0, u_snn.s_pool2},   POOL2_OUT) * 100) / POOL2_OUT,
                popcnt({2016'b0, u_snn.s_fc1_raw},     FC1_OUT),
                fc2_out_capture
            );
        end

        // 5. Output Inference Metrics Compilation
        $display("=================================================================");
        $display("  ACCUMULATED SPIKE COUNTS OVER %0d TIMESTEPS:", TIMESTEPS);
        $display("-----------------------------------------------------------------");
        $display("  Class 0 : %3d spikes", class_count[0]);
        $display("  Class 1 : %3d spikes", class_count[1]);
        $display("  Class 2 : %3d spikes", class_count[2]);
        $display("  Class 3 : %3d spikes", class_count[3]);

        // Evaluate Argmax Prediction Node
        best_cls = 0; 
        best_cnt = class_count[0];
        for (i=1; i<FC2_OUT; i=i+1) begin
            if (class_count[i] > best_cnt) begin
                best_cnt = class_count[i]; 
                best_cls = i;
            end
        end
        $display("-----------------------------------------------------------------");
        $display("  ► PREDICTED WINNING CLASS = %0d  (%0d spikes)", best_cls, best_cnt);
        $display("=================================================================\n");

        $finish;
    end

endmodule