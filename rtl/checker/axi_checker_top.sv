`timescale 1ns/1ns

import axi_checker_pkg::*;

// Top-level wrapper: everything the PL needs, packaged as one IP.
//
//   PS --AXI4-Lite--> CSR --> rogue master --> dummy slave
//                      ^           |
//                      |      (monitored bus)
//                      |           v
//                      +-- FIFO <- checker core (read-only tap)
//
// The only external interface is the AXI4-Lite slave port from the PS.
module axi_checker_top #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32
)(
    input  logic              ACLK,
    input  logic              ARESETn,

    // ---- AXI4-Lite slave port (from the Zynq PS) ----
    input  logic              S_AXI_AWVALID,
    input  logic [ADDR_W-1:0] S_AXI_AWADDR,
    output logic              S_AXI_AWREADY,
    input  logic              S_AXI_WVALID,
    input  logic [31:0]       S_AXI_WDATA,
    input  logic [3:0]        S_AXI_WSTRB,
    output logic              S_AXI_WREADY,
    output logic              S_AXI_BVALID,
    output logic [1:0]        S_AXI_BRESP,
    input  logic              S_AXI_BREADY,
    input  logic              S_AXI_ARVALID,
    input  logic [ADDR_W-1:0] S_AXI_ARADDR,
    output logic              S_AXI_ARREADY,
    output logic              S_AXI_RVALID,
    output logic [31:0]       S_AXI_RDATA,
    output logic [1:0]        S_AXI_RRESP,
    input  logic              S_AXI_RREADY,

    // ---- optional: bring violations out for an ILA / LED ----
    output logic              viol_any_o
);

    // ============================================================
    // internal monitored bus (rogue master <-> dummy slave)
    // ============================================================
    logic              m_AWVALID, m_AWREADY;
    logic [ADDR_W-1:0] m_AWADDR;
    logic              m_WVALID,  m_WREADY;
    logic [DATA_W-1:0] m_WDATA;
    logic              m_BVALID,  m_BREADY;
    logic [1:0]        m_BRESP;

    // read channels are unused in v1 (rogue master does writes only)
    logic              m_ARVALID = 1'b0, m_ARREADY = 1'b0;
    logic [ADDR_W-1:0] m_ARADDR  = '0;
    logic              m_RVALID  = 1'b0, m_RREADY  = 1'b0;
    logic [1:0]        m_RRESP   = 2'b00;

    // ---- control/status wiring ----
    logic              start;
    logic [3:0]        fault_mode;
    logic              busy;

    logic [N_VIOL-1:0] violations;
    logic              viol_any;

    logic [31:0]       fifo_ts;
    logic [N_VIOL-1:0] fifo_viol;
    logic              fifo_empty, fifo_full, fifo_overflow;
    logic [15:0]       fifo_count;
    logic              fifo_rd_en;

    assign viol_any_o = viol_any;

    // ============================================================
    // 1. CSR - the PS-facing register interface
    // ============================================================
    axi_lite_csr #(.ADDR_W(ADDR_W), .TS_W(32)) u_csr (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .S_AWVALID(S_AXI_AWVALID), .S_AWADDR(S_AXI_AWADDR), .S_AWREADY(S_AXI_AWREADY),
        .S_WVALID(S_AXI_WVALID),   .S_WDATA(S_AXI_WDATA),   .S_WSTRB(S_AXI_WSTRB),
        .S_WREADY(S_AXI_WREADY),
        .S_BVALID(S_AXI_BVALID),   .S_BRESP(S_AXI_BRESP),   .S_BREADY(S_AXI_BREADY),
        .S_ARVALID(S_AXI_ARVALID), .S_ARADDR(S_AXI_ARADDR), .S_ARREADY(S_AXI_ARREADY),
        .S_RVALID(S_AXI_RVALID),   .S_RDATA(S_AXI_RDATA),   .S_RRESP(S_AXI_RRESP),
        .S_RREADY(S_AXI_RREADY),
        .start(start), .fault_mode(fault_mode), .busy(busy),
        .fifo_ts(fifo_ts), .fifo_viol(fifo_viol),
        .fifo_empty(fifo_empty), .fifo_full(fifo_full),
        .fifo_overflow(fifo_overflow), .fifo_count(fifo_count),
        .fifo_rd_en(fifo_rd_en)
    );

    // ============================================================
    // 2. Rogue master - generates traffic, injects faults on command
    // ============================================================
    rogue_master #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_master (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .start(start), .fault_mode(fault_mode),
        .AWVALID(m_AWVALID), .AWADDR(m_AWADDR), .AWREADY(m_AWREADY),
        .WVALID(m_WVALID),   .WDATA(m_WDATA),   .WREADY(m_WREADY),
        .BVALID(m_BVALID),   .BRESP(m_BRESP),   .BREADY(m_BREADY),
        .busy(busy)
    );

    // ============================================================
    // 3. Dummy slave - the "device under observation".
    //    Stalls 2 cycles before accepting, so faults have a
    //    waiting window to violate (same as the sim slave).
    // ============================================================
    logic [1:0] aw_wait, w_wait;
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            aw_wait <= 0; w_wait <= 0; m_BVALID <= 0; m_BRESP <= 0;
        end else begin
            if (m_AWVALID && !m_AWREADY)      aw_wait <= aw_wait + 1;
            else if (m_AWVALID && m_AWREADY)  aw_wait <= 0;

            if (m_WVALID && !m_WREADY)        w_wait <= w_wait + 1;
            else if (m_WVALID && m_WREADY)    w_wait <= 0;

            if (m_WVALID && m_WREADY)         begin m_BVALID <= 1; m_BRESP <= 2'b00; end
            else if (m_BVALID && m_BREADY)    m_BVALID <= 0;
        end
    end
    assign m_AWREADY = m_AWVALID && (aw_wait >= 2);
    assign m_WREADY  = m_WVALID  && (w_wait  >= 2);

    // ============================================================
    // 4. Checker core - read-only tap on the monitored bus
    // ============================================================
    axi_checker_core #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_core (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .AWVALID(m_AWVALID), .AWREADY(m_AWREADY), .AWADDR(m_AWADDR),
        .WVALID(m_WVALID),   .WREADY(m_WREADY),   .WDATA(m_WDATA),
        .BVALID(m_BVALID),   .BREADY(m_BREADY),   .BRESP(m_BRESP),
        .ARVALID(m_ARVALID), .ARREADY(m_ARREADY), .ARADDR(m_ARADDR),
        .RVALID(m_RVALID),   .RREADY(m_RREADY),   .RRESP(m_RRESP),
        .violations(violations), .viol_any(viol_any)
    );

    // ============================================================
    // 5. Event FIFO - timestamps and buffers violations for the PS
    // ============================================================
    axi_event_fifo #(.DEPTH_LOG2(6), .TS_W(32)) u_fifo (
        .ACLK(ACLK), .ARESETn(ARESETn),
        .violations(violations),
        .rd_en(fifo_rd_en),
        .rd_timestamp(fifo_ts),
        .rd_violations(fifo_viol),
        .empty(fifo_empty), .full(fifo_full),
        .event_count(fifo_count), .overflow(fifo_overflow)
    );

endmodule