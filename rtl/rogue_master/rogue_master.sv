`timescale 1ns/1ns

// Rogue AXI4-Lite master: emits legal write traffic, and (later) on command
// via fault_mode injects exactly one protocol violation.
// Built for CONTROLLABILITY, not performance: sequential AW -> W -> B so each
// handshake is an isolated, aim-able fault-injection point.
module rogue_master #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32
)(
    input  logic              ACLK,
    input  logic              ARESETn,
    input  logic              start,       // pulse: begin one write transaction
    input  logic [3:0]        fault_mode,  // 0 = legal; nonzero = inject a fault (unused for now)

    // AXI4-Lite write channels (master drives AWVALID/WVALID/BREADY)
    output logic              AWVALID,
    output logic [ADDR_W-1:0] AWADDR,
    input  logic              AWREADY,
    output logic              WVALID,
    output logic [DATA_W-1:0] WDATA,
    input  logic              WREADY,
    input  logic              BVALID,
    input  logic [1:0]        BRESP,
    output logic              BREADY,

    output logic              busy         // high while a transaction is in flight
);

    typedef enum logic [1:0] { S_IDLE, S_AW, S_W, S_B } state_t;
    state_t state, next;

    // ---- 1. state register (the only memory) ----
    always_ff @(posedge ACLK) begin
        if (!ARESETn) state <= S_IDLE;
        else          state <= next;
    end

    // ---- 2. next-state logic (combinational) ----
    always_comb begin
        next = state;                             // default: hold
        case (state)
            S_IDLE: if (start)             next = S_AW;
            S_AW:   if (AWVALID && AWREADY) next = S_W;   // address accepted
            S_W:    if (WVALID  && WREADY)  next = S_B;   // data accepted
            S_B:    if (BVALID  && BREADY)  next = S_IDLE;// response accepted
            default:                        next = S_IDLE;
        endcase
    end

    // ---- 3. output logic (legal behavior; faults layered on later) ----
    always_comb begin
        // defaults: everything deasserted / safe
        AWVALID = 1'b0; AWADDR = 32'h40;
        WVALID  = 1'b0; WDATA  = 32'hDEAD_BEEF;
        BREADY  = 1'b0;

        case (state)
            S_AW: AWVALID = 1'b1;   // drive address, wait for AWREADY
            S_W:  WVALID  = 1'b1;   // drive data, wait for WREADY
            S_B:  BREADY  = 1'b1;   // ready to accept response
            default: ;              // IDLE: all low
        endcase
    end

    assign busy = (state != S_IDLE);

endmodule