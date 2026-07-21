`timescale 1ns/1ns

import axi_checker_pkg::*;

module tb_core;

  localparam int ADDR_W = 32;
  localparam int DATA_W = 32;

  logic ACLK, ARESETn;
  logic AWVALID, AWREADY;  logic [ADDR_W-1:0] AWADDR;
  logic WVALID,  WREADY;   logic [DATA_W-1:0] WDATA;
  logic BVALID,  BREADY;   logic [1:0]        BRESP;
  logic ARVALID, ARREADY;  logic [ADDR_W-1:0] ARADDR;
  logic RVALID,  RREADY;   logic [1:0]        RRESP;

  logic [N_VIOL-1:0] violations;
  logic              viol_any;

  initial ACLK = 0;
  always #5 ACLK = ~ACLK;

  // ---- DUT: the integrated checker ----
  axi_checker_core #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_core (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .AWVALID(AWVALID), .AWREADY(AWREADY), .AWADDR(AWADDR),
      .WVALID(WVALID),   .WREADY(WREADY),   .WDATA(WDATA),
      .BVALID(BVALID),   .BREADY(BREADY),   .BRESP(BRESP),
      .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR),
      .RVALID(RVALID),   .RREADY(RREADY),   .RRESP(RRESP),
      .violations(violations), .viol_any(viol_any)
  );

  // ---- decoder: bit index -> readable name (reuses the package map) ----
  function string viol_name(int idx);
      case (idx)
          V_C01_AW: return "C01 AW-retract";
          V_C01_W:  return "C01 W-retract";
          V_C01_B:  return "C01 B-retract";
          V_C01_AR: return "C01 AR-retract";
          V_C01_R:  return "C01 R-retract";
          V_C02_AW: return "C02 AW-stable";
          V_C02_W:  return "C02 W-stable";
          V_C02_B:  return "C02 B-stable";
          V_C02_AR: return "C02 AR-stable";
          V_C02_R:  return "C02 R-stable";
          V_C03:    return "C03 reset";
          V_C05:    return "C05 EXOKAY";
          V_C07:    return "C07 write-order";
          V_C08:    return "C08 read-order";
          V_C09:    return "C09 align";
          default:  return "unknown";
      endcase
  endfunction

  // ---- report: each cycle a violation is present, decode and print ----
  always_ff @(posedge ACLK) begin
      if (ARESETn && viol_any) begin
          for (int i = 0; i < N_VIOL; i++)
              if (violations[i])
                  $display("  [%0t] bit %0d -> %s", $time, i, viol_name(i));
      end
  end

  // ---- drive everything idle (legal) ----
  task idle;
      AWVALID=0; AWREADY=0; AWADDR=0;
      WVALID=0;  WREADY=0;  WDATA=0;
      BVALID=0;  BREADY=0;  BRESP=0;
      ARVALID=0; ARREADY=0; ARADDR=0;
      RVALID=0;  RREADY=0;  RRESP=0;
  endtask

  initial begin
      // ---- reset ----
      ARESETn=0; idle;
      repeat (2) @(negedge ACLK);
      ARESETn=1;
      @(negedge ACLK);

      // ================= FAULT 1: C01 on B channel =================
      // Do a legal AW+W handshake FIRST (so C07 is satisfied), THEN
      // stage the B retraction in isolation.  Expect: bit 2 only.
      $display("\n--- Fault 1: C01 on B (expect bit 2) ---");
      AWVALID=1; AWREADY=1; AWADDR=32'h40;    // AW handshakes
      WVALID=1;  WREADY=1;  WDATA=32'h1234;   // W handshakes -> C07 satisfied
      @(negedge ACLK);
      AWVALID=0; AWREADY=0; WVALID=0; WREADY=0;
      BVALID=1; BREADY=0; BRESP=2'b00;        // B waiting, READY low
      @(negedge ACLK);
      BVALID=0;                                // ILLEGAL retract (C01 on B)
      @(negedge ACLK);
      idle; repeat (2) @(negedge ACLK);

      // ================= FAULT 2: C09 misaligned read addr =========
      // End with a LEGAL AR handshake (not a yanked VALID) so no C01.
      // Expect: bit 14 only.
      $display("\n--- Fault 2: C09 misaligned AR (expect bit 14) ---");
      ARVALID=1; ARREADY=1; ARADDR=32'h1002;  // misaligned, but handshakes legally
      @(negedge ACLK);
      ARVALID=0; ARREADY=0;                    // dropped AFTER handshake -> legal
      @(negedge ACLK);
      idle; repeat (2) @(negedge ACLK);

      // ================= FAULT 3: C02 on W (data mutation) =========
      // Expect: bit 6 only.
      $display("\n--- Fault 3: C02 on W (expect bit 6) ---");
      WVALID=1; WREADY=0; WDATA=32'hAAAA;
      @(negedge ACLK);
      WDATA=32'hBBBB;                           // ILLEGAL: data moved while waiting
      @(negedge ACLK);
      WREADY=1;                                 // complete legally
      @(negedge ACLK);
      idle; repeat (2) @(negedge ACLK);

      // ================= LEGAL: clean write (expect SILENCE) =======
      $display("\n--- Legal write (expect silence) ---");
      AWVALID=1; AWREADY=1; AWADDR=32'h40;
      WVALID=1;  WREADY=1;  WDATA=32'h1234;
      @(negedge ACLK);
      AWVALID=0; AWREADY=0; WVALID=0; WREADY=0;
      BVALID=1; BREADY=1; BRESP=2'b00;          // legal response after AW+W
      @(negedge ACLK);
      idle; repeat (2) @(negedge ACLK);

      $display("\n--- done @ %0t ---", $time);
      $finish;
  end

endmodule