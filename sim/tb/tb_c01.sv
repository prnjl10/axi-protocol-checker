`timescale 1ns/1ns

module tb;

  logic        ACLK;
  logic        ARESETn;
  logic        AWVALID;
  logic        AWREADY;
  logic [31:0] AWADDR;

  logic        rtl_c01;
  logic        rtl_c02;

  initial ACLK = 0;
  always #5 ACLK = ~ACLK;

  // ---------- the RTL monitor under test ----------
  axi_handshake_monitor #(.PAYLOAD_W(32)) u_mon (
      .ACLK     (ACLK),
      .ARESETn  (ARESETn),
      .valid    (AWVALID),
      .ready    (AWREADY),
      .payload  (AWADDR),
      .viol_c01 (rtl_c01),
      .viol_c02 (rtl_c02)
  );

  // ---------- SVA reference (the golden spec) ----------
  a_c01: assert property (@(posedge ACLK) disable iff (!ARESETn)
           (AWVALID && !AWREADY) |=> AWVALID)
         else $error("SVA C01 @ %0t", $time);

  a_c02: assert property (@(posedge ACLK) disable iff (!ARESETn)
           (AWVALID && !AWREADY) |=> (!AWVALID || $stable(AWADDR)))
         else $error("SVA C02 @ %0t", $time);

  // ---------- report whenever the RTL monitor fires ----------
  always_ff @(posedge ACLK) begin
      if (ARESETn) begin
          if (rtl_c01) $display("RTL C01 @ %0t", $time);
          if (rtl_c02) $display("RTL C02 @ %0t", $time);
      end
  end

  // ---------- stimulus: driven on NEGEDGE so signals are stable
  //            at the posedge where the monitor and SVA sample them ----------
  initial begin
      ARESETn = 0; AWVALID = 0; AWREADY = 0; AWADDR = 32'h0;
      repeat (2) @(negedge ACLK);
      ARESETn = 1;
      @(negedge ACLK);

      // ---- Scenario A: legal transaction (both should stay SILENT) ----
      $display("\n--- A: legal transaction ---");
      AWVALID = 1; AWREADY = 0; AWADDR = 32'h40;
      @(negedge ACLK);
      AWREADY = 1;                  // handshake completes
      @(negedge ACLK);
      AWVALID = 0; AWREADY = 0;     // legal drop
      @(negedge ACLK);
      repeat (2) @(negedge ACLK);

      // ---- Scenario B: illegal retraction (C01 only) ----
      $display("\n--- B: retraction ---");
      AWVALID = 1; AWREADY = 0; AWADDR = 32'h40;
      @(negedge ACLK);
      AWVALID = 0;                  // ILLEGAL: retract before handshake
      @(negedge ACLK);
      repeat (2) @(negedge ACLK);

      // ---- Scenario C: payload mutation (C02 only) ----
      $display("\n--- C: payload mutation ---");
      AWVALID = 1; AWREADY = 0; AWADDR = 32'h40;
      @(negedge ACLK);
      AWADDR = 32'h44;              // ILLEGAL: address moved while waiting
      @(negedge ACLK);
      AWREADY = 1;                  // complete the handshake legally
      @(negedge ACLK);
      AWVALID = 0; AWREADY = 0;     // now the drop is legal - no C01
      repeat (3) @(negedge ACLK);

      $display("\n--- done @ %0t ---", $time);
      $finish;
  end

endmodule