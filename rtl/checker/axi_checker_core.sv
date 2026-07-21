`timescale 1ns/1ns

import axi_checker_pkg::*;

// Top-level AXI4-Lite checker: wires all per-check monitors into one
// unified violation vector. Bit index = check ID (see axi_checker_pkg).
module axi_checker_core #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32
)(
    input  logic              ACLK,
    input  logic              ARESETn,

    // ---- monitored AXI4-Lite bus (all read-only taps) ----
    input  logic              AWVALID, AWREADY,
    input  logic [ADDR_W-1:0] AWADDR,
    input  logic              WVALID,  WREADY,
    input  logic [DATA_W-1:0] WDATA,
    input  logic              BVALID,  BREADY,
    input  logic [1:0]        BRESP,
    input  logic              ARVALID, ARREADY,
    input  logic [ADDR_W-1:0] ARADDR,
    input  logic              RVALID,  RREADY,
    input  logic [1:0]        RRESP,

    // ---- unified outputs ----
    output logic [N_VIOL-1:0] violations,
    output logic              viol_any
);

    // ============================================================
    // C01/C02 handshake monitors - one per channel.
    // Each instance drives its channel's C01 and C02 bits.
    // ============================================================

    // --- AW channel (payload = AWADDR) ---
    axi_handshake_monitor #(.PAYLOAD_W(ADDR_W)) u_hs_aw (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .valid(AWVALID), .ready(AWREADY), .payload(AWADDR),
        .viol_c01(violations[V_C01_AW]),
        .viol_c02(violations[V_C02_AW])
    );

    // --- W channel (payload = WDATA: write data must stay stable while waiting) ---
    axi_handshake_monitor #(.PAYLOAD_W(DATA_W)) u_hs_w (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .valid(WVALID), .ready(WREADY), .payload(WDATA),
        .viol_c01(violations[V_C01_W]),
        .viol_c02(violations[V_C02_W])
    );

    // --- B channel (payload = BRESP) ---
    axi_handshake_monitor #(.PAYLOAD_W(2)) u_hs_b (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .valid(BVALID), .ready(BREADY), .payload(BRESP),
        .viol_c01(violations[V_C01_B]),
        .viol_c02(violations[V_C02_B])
    );

    // --- AR channel (payload = ARADDR) ---
    axi_handshake_monitor #(.PAYLOAD_W(ADDR_W)) u_hs_ar (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .valid(ARVALID), .ready(ARREADY), .payload(ARADDR),
        .viol_c01(violations[V_C01_AR]),
        .viol_c02(violations[V_C02_AR])
    );

    // --- R channel (payload = RRESP) ---
    axi_handshake_monitor #(.PAYLOAD_W(2)) u_hs_r (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .valid(RVALID), .ready(RREADY), .payload(RRESP),
        .viol_c01(violations[V_C01_R]),
        .viol_c02(violations[V_C02_R])
    );

    // ============================================================
    // C03/C05/C09 combinational checks - one instance, all channels.
    // ============================================================
    axi_lite_comb_checks #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_comb (
        .ARESETn(ARESETn),
        .AWVALID(AWVALID), .WVALID(WVALID), .BVALID(BVALID),
        .ARVALID(ARVALID), .RVALID(RVALID),
        .AWADDR(AWADDR), .ARADDR(ARADDR),
        .BRESP(BRESP), .RRESP(RRESP),
        .viol_c03(violations[V_C03]),
        .viol_c05(violations[V_C05]),
        .viol_c09(violations[V_C09])
    );

    // ============================================================
    // C07/C08 ordering monitor - one instance.
    // ============================================================
    axi_ordering_monitor u_ord (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WVALID(WVALID),   .WREADY(WREADY),
        .BVALID(BVALID),   .BREADY(BREADY),
        .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RVALID(RVALID),   .RREADY(RREADY),
        .viol_c07(violations[V_C07]),
        .viol_c08(violations[V_C08])
    );

    // ============================================================
    // "any violation this cycle" - OR-reduction of the whole vector.
    // ============================================================
    assign viol_any = |violations;

endmodule