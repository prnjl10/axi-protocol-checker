`timescale 1ns/1ns

// Shared constants for the AXI checker.
// The violation-bit map is the single source of truth - RTL, the CSR layer,
// and the PS/dashboard all reference these indices.
package axi_checker_pkg;

    localparam int N_VIOL = 15;   // total violation bits

    // ---- violation bit indices (bit position = check ID) ----
    localparam int V_C01_AW = 0;
    localparam int V_C01_W  = 1;
    localparam int V_C01_B  = 2;
    localparam int V_C01_AR = 3;
    localparam int V_C01_R  = 4;
    localparam int V_C02_AW = 5;
    localparam int V_C02_W  = 6;
    localparam int V_C02_B  = 7;
    localparam int V_C02_AR = 8;
    localparam int V_C02_R  = 9;
    localparam int V_C03    = 10;  // reset (all channels)
    localparam int V_C05    = 11;  // EXOKAY (B/R)
    localparam int V_C07    = 12;  // write ordering
    localparam int V_C08    = 13;  // read ordering
    localparam int V_C09    = 14;  // address alignment (AW/AR)

endpackage