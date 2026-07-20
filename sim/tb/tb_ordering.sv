`timescale 1ns/1ns

module tb_ordering;

  logic ACLK, ARESETn;
  logic AWVALID, AWREADY, WVALID, WREADY, BVALID, BREADY;
  logic ARVALID, ARREADY, RVALID, RREADY;
  logic viol_c07, viol_c08;

  initial ACLK = 0;
  always #5 ACLK = ~ACLK;

  // ---- DUT ----
  axi_ordering_monitor u_ord (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .AWVALID(AWVALID), .AWREADY(AWREADY),
      .WVALID(WVALID),   .WREADY(WREADY),
      .BVALID(BVALID),   .BREADY(BREADY),
      .ARVALID(ARVALID), .ARREADY(ARREADY),
      .RVALID(RVALID),   .RREADY(RREADY),
      .viol_c07(viol_c07), .viol_c08(viol_c08)
  );

  // ---- report any violation each clock ----
  always_ff @(posedge ACLK) begin
      if (ARESETn) begin
          if (viol_c07) $display("RTL C07 @ %0t", $time);
          if (viol_c08) $display("RTL C08 @ %0t", $time);
      end
  end

  // drive everything idle
  task idle;
      AWVALID=0; AWREADY=0; WVALID=0; WREADY=0; BVALID=0; BREADY=0;
      ARVALID=0; ARREADY=0; RVALID=0; RREADY=0;
  endtask

  initial begin
      ARESETn = 0; idle;
      repeat (2) @(negedge ACLK);
      ARESETn = 1;
      @(negedge ACLK);

      // ============ Scenario A: LEGAL write (must be SILENT) ============
      // AW and W handshake first, THEN B - the correct order.
      $display("\n--- A: legal write (silent) ---");
      AWVALID=1; AWREADY=1;          // AW handshakes this cycle
      WVALID=1;  WREADY=1;           // W handshakes this cycle -> both flags set
      @(negedge ACLK);
      AWVALID=0; AWREADY=0; WVALID=0; WREADY=0;
      @(negedge ACLK);               // a gap - flags hold at 1
      BVALID=1; BREADY=1;            // B now - legal, prerequisites met
      @(negedge ACLK);
      idle;                          // B handshake cleared the flags
      repeat (2) @(negedge ACLK);

      // ============ Scenario B: C07 fault - B before AW/W ============
      // Slave asserts BVALID with NO prior AW or W handshake.
      $display("\n--- B: C07 fault (B before AW/W) ---");
      BVALID=1; BREADY=1;            // ILLEGAL: response with no request accepted
      @(negedge ACLK);               // aw_done=0, w_done=0 -> viol_c07 fires
      idle;
      repeat (2) @(negedge ACLK);

      // ============ Scenario C: C08 fault - R before AR ============
      // Slave asserts RVALID with NO prior AR handshake.
      $display("\n--- C: C08 fault (R before AR) ---");
      RVALID=1; RREADY=1;            // ILLEGAL: read data with no address accepted
      @(negedge ACLK);               // ar_done=0 -> viol_c08 fires
      idle;
      repeat (2) @(negedge ACLK);

      // ============ Scenario D: LEGAL read (must be SILENT) ============
      // AR handshakes first, THEN R.
      $display("\n--- D: legal read (silent) ---");
      ARVALID=1; ARREADY=1;          // AR handshakes -> ar_done set
      @(negedge ACLK);
      ARVALID=0; ARREADY=0;
      @(negedge ACLK);
      RVALID=1; RREADY=1;            // R now - legal, AR already done
      @(negedge ACLK);
      idle;
      repeat (2) @(negedge ACLK);

      $display("\n--- done @ %0t ---", $time);
      $finish;
  end

endmodule