    module neuron #(
        parameter beta=112,
        parameter thresh = 16'd255
    ) (
        input  [ 0:0] spike_in,
        input  [15:0] weight,
        input clk,reset,
        output reg [0:0] spike_out,
        output reg [17:0] thresh_vol
    );
        reg [17:0] decay_voltage;
        reg [1:0] cooldown;
        reg [17:0] final_vol;
        always @(posedge clk) begin
            if(reset) begin
                decay_voltage<= 18'b0;
                cooldown <= 2'b0;
                thresh_vol <= decay_voltage;
            end
            else if(cooldown != 0) begin
                decay_voltage <= decay_voltage - ((decay_voltage*beta) >> 3);
                spike_out <= 0;
                cooldown <= cooldown -1'b1;
                thresh_vol <= decay_voltage;
            end
            else begin
                final_vol = (decay_voltage - ((decay_voltage*beta) >> 3)) + (spike_in ? weight : 16'b0);
                thresh_vol <= final_vol;
                if(final_vol > thresh) begin
                    spike_out <= 1;
                    cooldown <= 2'b11;
                    decay_voltage <= 18'b0;
                end
                else spike_out <= 0;
                
            end
        end
    endmodule
    
    
