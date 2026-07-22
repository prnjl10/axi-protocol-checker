`timescale 1ns/1ns

// Rogue AXI4-Lite master: emits legal write traffic, and on command
// (fault_mode) injects exactly one protocol violation.
// Sequential AW -> W -> B FSM: each handshake is an isolated fault-injection point.
module rogue_master #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32
)(
    input  logic              ACLK,
    input  logic              ARESETn,
    input  logic              start,
    input  logic [3:0]        fault_mode,

    output logic              AWVALID,
    output logic [ADDR_W-1:0] AWADDR,
    input  logic              AWREADY,
    output logic              WVALID,
    output logic [DATA_W-1:0] WDATA,
    input  logic              WREADY,
    input  logic              BVALID,
    input  logic [1:0]        BRESP,
    output logic              BREADY,

    output logic              busy
);

    // ---- fault mode encodings ----
    localparam logic [3:0] F_NONE    = 4'd0;  // fully legal traffic
    localparam logic [3:0] F_C01_AW  = 4'd1;  // retract AWVALID before AWREADY
    localparam logic [3:0] F_C02_AW  = 4'd2;  // mutate AWADDR while waiting
    localparam logic [3:0] F_C01_W   = 4'd3;  // retract WVALID before WREADY
    localparam logic [3:0] F_C02_W   = 4'd4;  // mutate WDATA while waiting
    localparam logic [3:0] F_C09     = 4'd5;  // misaligned address

    typedef enum logic [1:0] { S_IDLE, S_AW, S_W, S_B } state_t;
    state_t state, next;

    // ---- 1. state register ----
    always_ff @(posedge ACLK) begin
        if (!ARESETn) state <= S_IDLE;
        else          state <= next;
    end

    // ---- dwell counter: how many cycles we've been parked in this state ----
    // Fault injection needs a "waiting window" to violate, so we count it.
    logic [3:0] dwell;
    always_ff @(posedge ACLK) begin
        if (!ARESETn)            dwell <= 4'd0;
        else if (state != next)  dwell <= 4'd0;   // reset on state change
        else                     dwell <= dwell + 4'd1;
    end

    // ---- 2. next-state logic ----
    always_comb begin
        next = state;
        case (state)
            S_IDLE: if (start)              next = S_AW;
            S_AW:   if (AWVALID && AWREADY) next = S_W;
            S_W:    if (WVALID  && WREADY)  next = S_B;
            S_B:    if (BVALID  && BREADY)  next = S_IDLE;
            default:                        next = S_IDLE;
        endcase
    end

    // ---- 3. output logic: legal behavior, with faults layered on ----
    always_comb begin
        // defaults
        AWVALID = 1'b0;
        AWADDR  = (fault_mode == F_C09) ? 32'h42 : 32'h40;  // 0x42 is misaligned
        WVALID  = 1'b0;
        WDATA   = 32'hAAAA_AAAA;
        BREADY  = 1'b0;

        case (state)
            S_AW: begin
                // C01 fault: after waiting one cycle, illegally drop VALID
                AWVALID = (fault_mode == F_C01_AW && dwell >= 4'd1) ? 1'b0 : 1'b1;
                // C02 fault: after waiting one cycle, illegally change the address
                if (fault_mode == F_C02_AW && dwell >= 4'd1)
                    AWADDR = 32'h44;                 // mutated mid-wait
            end

            S_W: begin
                WVALID = (fault_mode == F_C01_W && dwell >= 4'd1) ? 1'b0 : 1'b1;
                if (fault_mode == F_C02_W && dwell >= 4'd1)
                    WDATA = 32'hBBBB_BBBB;           // mutated mid-wait
            end

            S_B: BREADY = 1'b1;

            default: ;
        endcase
    end

    assign busy = (state != S_IDLE);

endmodule