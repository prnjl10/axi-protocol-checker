`timescale 1ns/1ns

import axi_checker_pkg::*;

// Event FIFO: converts raw per-cycle violation bits into timestamped events.
//   - edge-detects so one illegal act = one event (not one per cycle)
//   - timestamps each event from a free-running cycle counter
//   - buffers events until the PS drains them
//   - flags overflow rather than silently losing events
module axi_event_fifo #(
    parameter int DEPTH_LOG2 = 6,          // 2^6 = 64 entries
    parameter int TS_W       = 32          // timestamp width
)(
    input  logic                  ACLK,
    input  logic                  ARESETn,

    // ---- from the checker core ----
    input  logic [N_VIOL-1:0]     violations,

    // ---- read side (later driven by the CSR/PS interface) ----
    input  logic                  rd_en,        // pulse: pop one event
    output logic [TS_W-1:0]       rd_timestamp,
    output logic [N_VIOL-1:0]     rd_violations,
    output logic                  empty,
    output logic                  full,

    // ---- status ----
    output logic [15:0]           event_count,  // events currently buffered
    output logic                  overflow      // sticky: at least one event was lost
);

    localparam int DEPTH = 1 << DEPTH_LOG2;

    // ============================================================
    // 1. Free-running timestamp counter
    // ============================================================
    logic [TS_W-1:0] cycle_count;
    always_ff @(posedge ACLK) begin
        if (!ARESETn) cycle_count <= '0;
        else          cycle_count <= cycle_count + 1'b1;
    end

    // ============================================================
    // 2. Edge detection: level -> single-cycle pulse
    //    A bit passes only on a fresh 0->1 transition.
    // ============================================================
    logic [N_VIOL-1:0] viol_prev;
    always_ff @(posedge ACLK) begin
        if (!ARESETn) viol_prev <= '0;
        else          viol_prev <= violations;
    end

    logic [N_VIOL-1:0] viol_pulse;
    assign viol_pulse = violations & ~viol_prev;

    logic push;
    assign push = |viol_pulse;              // any fresh violation this cycle

    // ============================================================
    // 3. Circular FIFO storage
    // ============================================================
    logic [TS_W-1:0]   ts_mem   [DEPTH];
    logic [N_VIOL-1:0] viol_mem [DEPTH];

    logic [DEPTH_LOG2-1:0] wr_ptr, rd_ptr;
    logic [DEPTH_LOG2:0]   count;           // one extra bit to distinguish full/empty

    assign empty = (count == 0);
    assign full  = (count == DEPTH);
    assign event_count = {{(16-DEPTH_LOG2-1){1'b0}}, count};

    // write side
    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            wr_ptr <= '0;
        end else if (push && !full) begin
            ts_mem[wr_ptr]   <= cycle_count;
            viol_mem[wr_ptr] <= viol_pulse;   // store the PULSE, not the level
            wr_ptr           <= wr_ptr + 1'b1;
        end
    end

    // read side
    always_ff @(posedge ACLK) begin
        if (!ARESETn) rd_ptr <= '0;
        else if (rd_en && !empty) rd_ptr <= rd_ptr + 1'b1;
    end

    assign rd_timestamp  = ts_mem[rd_ptr];
    assign rd_violations = viol_mem[rd_ptr];

    // occupancy counter
    always_ff @(posedge ACLK) begin
        if (!ARESETn) count <= '0;
        else begin
            case ({push && !full, rd_en && !empty})
                2'b10:   count <= count + 1'b1;   // write only
                2'b01:   count <= count - 1'b1;   // read only
                default: count <= count;          // both or neither
            endcase
        end
    end

    // ============================================================
    // 4. Overflow: sticky flag if an event arrived with no room
    // ============================================================
    always_ff @(posedge ACLK) begin
        if (!ARESETn)          overflow <= 1'b0;
        else if (push && full) overflow <= 1'b1;   // sticky until reset
    end

endmodule