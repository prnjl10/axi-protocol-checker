`timescale 1ns/1ns

// Synthesizable handshake monitor for one AXI channel.
// Hand-translation of the C01/C02 SVA properties.
module axi_handshake_monitor #(
    parameter int PAYLOAD_W = 32
)(
    input  logic                 ACLK,
    input  logic                 ARESETn,
    input  logic                 valid,
    input  logic                 ready,
    input  logic [PAYLOAD_W-1:0] payload,
    output logic                 viol_c01,
    output logic                 viol_c02
);

    // History registers - how hardware remembers the previous cycle.
    logic                 valid_prev;
    logic                 ready_prev;
    logic [PAYLOAD_W-1:0] payload_prev;

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            valid_prev   <= 1'b0;
            ready_prev   <= 1'b0;
            payload_prev <= '0;
        end else begin
            valid_prev   <= valid;
            ready_prev   <= ready;
            payload_prev <= payload;
        end
    end

    // C01: was waiting last cycle, VALID has now dropped.
    assign viol_c01 = valid_prev && !ready_prev && !valid;

    // C02: was waiting last cycle, still waiting now, payload moved.
    assign viol_c02 = valid_prev && !ready_prev && valid
                                 && (payload != payload_prev);

endmodule