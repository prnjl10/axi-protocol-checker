`timescale 1ns/1ns

import axi_checker_pkg::*;

// AXI4-Lite SLAVE: the PS-facing register interface.
// Register map (word-aligned, 32-bit):
//   0x00 CTRL     R/W  bit0 = start pulse, bits[7:4] = fault_mode
//   0x04 STATUS   R    bit0 empty, bit1 full, bit2 overflow, bit3 busy
//   0x08 COUNT    R    events currently buffered
//   0x0C EV_TS    R    timestamp of event at FIFO head
//   0x10 EV_VIOL  R    violation vector of event at head
//   0x14 EV_POP   W    write anything -> pop the head event
//
// Write path is sequential: AW must be accepted before WREADY is asserted
// (legal - READY may wait). Simplifies the FSM; the PS never needs W-first.
module axi_lite_csr #(
    parameter int ADDR_W = 32,
    parameter int TS_W   = 32
)(
    input  logic              ACLK,
    input  logic              ARESETn,

    // ---- AXI4-Lite slave port (from the PS) ----
    input  logic              S_AWVALID,
    input  logic [ADDR_W-1:0] S_AWADDR,
    output logic              S_AWREADY,
    input  logic              S_WVALID,
    input  logic [31:0]       S_WDATA,
    input  logic [3:0]        S_WSTRB,
    output logic              S_WREADY,
    output logic              S_BVALID,
    output logic [1:0]        S_BRESP,
    input  logic              S_BREADY,
    input  logic              S_ARVALID,
    input  logic [ADDR_W-1:0] S_ARADDR,
    output logic              S_ARREADY,
    output logic              S_RVALID,
    output logic [31:0]       S_RDATA,
    output logic [1:0]        S_RRESP,
    input  logic              S_RREADY,

    // ---- to the rogue master ----
    output logic              start,
    output logic [3:0]        fault_mode,
    input  logic              busy,

    // ---- to/from the event FIFO ----
    input  logic [TS_W-1:0]     fifo_ts,
    input  logic [N_VIOL-1:0]   fifo_viol,
    input  logic                fifo_empty,
    input  logic                fifo_full,
    input  logic                fifo_overflow,
    input  logic [15:0]         fifo_count,
    output logic                fifo_rd_en
);

    // register offsets (word addresses)
    localparam logic [3:0] R_CTRL    = 4'h0;
    localparam logic [3:0] R_STATUS  = 4'h4;
    localparam logic [3:0] R_COUNT   = 4'h8;
    localparam logic [3:0] R_EV_TS   = 4'hC;
    localparam logic [3:0] R_EV_VIOL = 4'h0;   // 0x10 -> low nibble 0
    localparam logic [3:0] R_EV_POP  = 4'h4;   // 0x14 -> low nibble 4

    // use bits [7:0] of the address to decode (enough for our map)
    logic [7:0] wr_addr, rd_addr;

    // ============================================================
    // WRITE PATH: AW accepted first, then W, then B response
    // ============================================================
    typedef enum logic [1:0] { W_IDLE, W_DATA, W_RESP } wstate_t;
    wstate_t wstate;

    logic [3:0] fault_mode_r;

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            wstate       <= W_IDLE;
            wr_addr      <= '0;
            fault_mode_r <= '0;
            start        <= 1'b0;
            fifo_rd_en   <= 1'b0;
            S_BRESP      <= 2'b00;
        end else begin
            start      <= 1'b0;      // start is a one-cycle pulse
            fifo_rd_en <= 1'b0;      // so is the FIFO pop

            case (wstate)
                W_IDLE: begin
                    if (S_AWVALID && S_AWREADY) begin
                        wr_addr <= S_AWADDR[7:0];
                        wstate  <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (S_WVALID && S_WREADY) begin
                        case (wr_addr)
                            8'h00: begin                    // CTRL
                                start        <= S_WDATA[0];
                                fault_mode_r <= S_WDATA[7:4];
                            end
                            8'h14: fifo_rd_en <= 1'b1;      // EV_POP
                            default: ;                      // ignore others
                        endcase
                        S_BRESP <= 2'b00;                   // OKAY
                        wstate  <= W_RESP;
                    end
                end

                W_RESP: begin
                    if (S_BVALID && S_BREADY) wstate <= W_IDLE;
                end

                default: wstate <= W_IDLE;
            endcase
        end
    end

    assign S_AWREADY = (wstate == W_IDLE);
    assign S_WREADY  = (wstate == W_DATA);   // only after AW accepted
    assign S_BVALID  = (wstate == W_RESP);
    assign fault_mode = fault_mode_r;

    // ============================================================
    // READ PATH: AR accepted, then R data returned
    // ============================================================
    typedef enum logic { R_IDLE, R_DATA } rstate_t;
    rstate_t rstate;

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            rstate  <= R_IDLE;
            rd_addr <= '0;
            S_RDATA <= '0;
            S_RRESP <= 2'b00;
        end else begin
            case (rstate)
                R_IDLE: begin
                    if (S_ARVALID && S_ARREADY) begin
                        rd_addr <= S_ARADDR[7:0];
                        // decode and latch the read data
                        case (S_ARADDR[7:0])
                            8'h00: S_RDATA <= {24'd0, fault_mode_r, 3'd0, 1'b0};
                            8'h04: S_RDATA <= {28'd0, busy, fifo_overflow,
                                                       fifo_full, fifo_empty};
                            8'h08: S_RDATA <= {16'd0, fifo_count};
                            8'h0C: S_RDATA <= fifo_ts;
                            8'h10: S_RDATA <= {{(32-N_VIOL){1'b0}}, fifo_viol};
                            default: S_RDATA <= 32'hDEAD_BEEF;
                        endcase
                        S_RRESP <= 2'b00;    // OKAY
                        rstate  <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (S_RVALID && S_RREADY) rstate <= R_IDLE;
                end

                default: rstate <= R_IDLE;
            endcase
        end
    end

    assign S_ARREADY = (rstate == R_IDLE);
    assign S_RVALID  = (rstate == R_DATA);

endmodule