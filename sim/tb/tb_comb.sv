`timescale 1ns/1ns

module tb_comb;

  logic              ACLK;
  logic              ARESETn;
  logic              AWVALID, WVALID, BVALID, ARVALID, RVALID;
  logic [31:0]       AWADDR, ARADDR;
  logic [1:0]        BRESP, RRESP;

  logic viol_c03, viol_c05, viol_c09;

  initial ACLK = 0;
  always #5 ACLK = ~ACLK;

  // ---- DUT: the combinational checker ----
  axi_lite_comb_checks #(.ADDR_W(32), .DATA_W(32)) u_chk (
      .ARESETn(ARESETn),
      .AWVALID(AWVALID), .WVALID(WVALID), .BVALID(BVALID),
      .ARVALID(ARVALID), .RVALID(RVALID),
      .AWADDR(AWADDR), .ARADDR(ARADDR),
      .BRESP(BRESP), .RRESP(RRESP),
      .viol_c03(viol_c03), .viol_c05(viol_c05), .viol_c09(viol_c09)
  );

  // ---- report any violation every clock ----
  always_ff @(posedge ACLK) begin
      if (viol_c03) $display("RTL C03 @ %0t", $time);
      if (viol_c05) $display("RTL C05 @ %0t", $time);
      if (viol_c09) $display("RTL C09 @ %0t", $time);
  end

  // helper: drive everything to a known idle state
  task idle;
      AWVALID=0; WVALID=0; BVALID=0; ARVALID=0; RVALID=0;
      AWADDR=0; ARADDR=0; BRESP=0; RRESP=0;
  endtask

  initial begin
      // ============ C03: VALID high DURING reset ============
      $display("\n--- C03: VALID high during reset ---");
      ARESETn = 0;
      idle;
      AWVALID = 1;         // ILLEGAL: VALID asserted while reset is active
      @(negedge ACLK);     // checker samples -> C03 fires
      AWVALID = 0;

      // release reset, go idle and clean
      idle;
      ARESETn = 1;
      @(negedge ACLK);

      // ============ C05: slave returns EXOKAY on Lite ============
      $display("\n--- C05: EXOKAY response ---");
      BVALID = 1; BRESP = 2'b01;   // ILLEGAL: EXOKAY on a Lite bus
      @(negedge ACLK);             // C05 fires
      idle;                        // clear it

      @(negedge ACLK);

      // ============ C09: misaligned address ============
      $display("\n--- C09: misaligned address ---");
      ARVALID = 1; ARADDR = 32'h1002;   // ILLEGAL: 0x1002 -> bits [1:0] = 10
      @(negedge ACLK);                  // C09 fires
      idle;                             // clear it

      @(negedge ACLK);

      // ============ legal: aligned addr + OKAY response (must be SILENT) ============
      $display("\n--- legal traffic (should be silent) ---");
      AWVALID=1; AWADDR=32'h40;   // aligned
      BVALID=1;  BRESP=2'b00;     // OKAY
      @(negedge ACLK);
      idle;
      @(negedge ACLK);

      repeat (2) @(negedge ACLK);
      $display("\n--- done @ %0t ---", $time);
      $finish;
  end

endmodule