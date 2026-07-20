`timescale 1ns/1ns

// Combinational AXI4-Lite checks: C03, C05, C09.
// No history registers - each check judges the current cycle's wires alone.
//
// Scoping notes (see docs/traceability_matrix.md):
//   C04 - X/unknown design-integrity check, simulation-only (no X in hardware).
//         Lives in the SVA, not here.
//   C06 - write-strobe legality deferred to v2. On Lite, WSTRB is declared
//         [DATA_W/8-1:0], so it cannot physically carry bits outside its own
//         lanes; the check is unfalsifiable. It becomes meaningful in v2, where
//         AxSIZE and the address constrain which lanes may legally assert.
module axi_lite_comb_checks #(
    parameter int ADDR_W = 32,
    parameter int DATA_W = 32
)(
    input  logic                ARESETn,

    // all five channel VALIDs (C03 watches every one)
    input  logic                AWVALID,
    input  logic                WVALID,
    input  logic                BVALID,
    input  logic                ARVALID,
    input  logic                RVALID,

    // payloads
    input  logic [ADDR_W-1:0]   AWADDR,
    input  logic [ADDR_W-1:0]   ARADDR,
    input  logic [1:0]          BRESP,
    input  logic [1:0]          RRESP,

    output logic                viol_c03,   // VALID high during reset
    output logic                viol_c05,   // EXOKAY on a Lite bus
    output logic                viol_c09    // address not aligned to bus width
);

    // ---- C03: no VALID may be high while reset is asserted ----
    // NOTE: deliberately NOT gated by ARESETn - this check exists to police reset.
    assign viol_c03 = !ARESETn && (AWVALID || WVALID || BVALID || ARVALID || RVALID);

    // ---- C05: EXOKAY (2'b01) is illegal on AXI4-Lite (no AxLOCK exists) ----
    // A response code only means anything while its channel's VALID is high.
    assign viol_c05 = (BVALID && (BRESP == 2'b01)) ||
                      (RVALID && (RRESP == 2'b01));

    // ---- C09: addresses must be aligned to the data-bus width ----
    // 32-bit bus -> 4 bytes -> bottom 2 bits must be zero.
    // Parameterized: widen DATA_W and the check follows automatically.
    localparam int ALIGN_BITS = $clog2(DATA_W/8);

    assign viol_c09 = (AWVALID && (AWADDR[ALIGN_BITS-1:0] != 0)) ||
                      (ARVALID && (ARADDR[ALIGN_BITS-1:0] != 0));

endmodule