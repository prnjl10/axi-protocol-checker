`timescale 1ns/1ns

// C07/C08 ordering monitor - stateful (scoreboard).
// C07: B must not assert before both AW and W have handshaked.
// C08: R must not assert before AR has handshaked.
module axi_ordering_monitor (
    input  logic ACLK,
    input  logic ARESETn,
    input  logic AWVALID, AWREADY,
    input  logic WVALID,  WREADY,
    input  logic BVALID,  BREADY,
    input  logic ARVALID, ARREADY,
    input  logic RVALID,  RREADY,
    output logic viol_c07,
    output logic viol_c08
);

    // ---- scoreboard flags: set on handshake, clear on response handshake ----
    logic aw_done, w_done, ar_done;

    always_ff @(posedge ACLK) begin
        if (!ARESETn) begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
            ar_done <= 1'b0;
        end else begin
            // set wins over clear on same-cycle collision (set checked first)
            if (AWVALID && AWREADY)    aw_done <= 1'b1;
            else if (BVALID && BREADY) aw_done <= 1'b0;

            if (WVALID && WREADY)      w_done <= 1'b1;
            else if (BVALID && BREADY) w_done <= 1'b0;

            if (ARVALID && ARREADY)    ar_done <= 1'b1;
            else if (RVALID && RREADY) ar_done <= 1'b0;
        end
    end

    // ---- bypass: "done in a past cycle OR completing right now" ----
    logic aw_ok, w_ok, ar_ok;
    assign aw_ok = aw_done || (AWVALID && AWREADY);
    assign w_ok  = w_done  || (WVALID  && WREADY);
    assign ar_ok = ar_done || (ARVALID && ARREADY);

    // ---- violation: response asserted before its prerequisites ----
    // C07: BVALID high, but AW and/or W not (yet) done.
    assign viol_c07 = BVALID && !(aw_ok && w_ok);

    // C08: RVALID high, but AR not (yet) done.
    assign viol_c08 = RVALID && !ar_ok;

endmodule