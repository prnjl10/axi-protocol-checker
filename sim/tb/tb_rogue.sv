`timescale 1ns/1ns

module tb_rogue;

  localparam int ADDR_W = 32;
  localparam int DATA_W = 32;

  logic ACLK, ARESETn;
  logic start;
  logic [3:0] fault_mode;

  logic AWVALID; logic [ADDR_W-1:0] AWADDR; logic AWREADY;
  logic WVALID;  logic [DATA_W-1:0] WDATA;  logic WREADY;
  logic BVALID;  logic [1:0] BRESP;         logic BREADY;
  logic busy;

  initial ACLK = 0;
  always #5 ACLK = ~ACLK;

  // ---- DUT: the rogue master ----
  rogue_master #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_master (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .start(start), .fault_mode(fault_mode),
      .AWVALID(AWVALID), .AWADDR(AWADDR), .AWREADY(AWREADY),
      .WVALID(WVALID),   .WDATA(WDATA),   .WREADY(WREADY),
      .BVALID(BVALID),   .BRESP(BRESP),   .BREADY(BREADY),
      .busy(busy)
  );

  // ============================================================
  // Minimal ALWAYS-READY slave.
  //   - AWREADY, WREADY tied high (accept immediately)
  //   - BVALID raised the cycle after W is accepted, held until BREADY
  // ============================================================
  assign AWREADY = 1'b1;
  assign WREADY  = 1'b1;

  // B response: assert BVALID after the write data is accepted,
  // clear it once the master accepts (BREADY high).
  always_ff @(posedge ACLK) begin
      if (!ARESETn) begin
          BVALID <= 1'b0;
          BRESP  <= 2'b00;
      end else begin
          if (WVALID && WREADY) begin      // data just accepted -> response ready
              BVALID <= 1'b1;
              BRESP  <= 2'b00;             // OKAY
          end else if (BVALID && BREADY) begin  // master accepted response
              BVALID <= 1'b0;
          end
      end
  end

  // ---- trace the FSM state each cycle ----
  always_ff @(posedge ACLK) begin
      if (ARESETn)
          $display("[%0t] state=%s AWVALID=%b WVALID=%b BREADY=%b BVALID=%b busy=%b",
                   $time, u_master.state.name(), AWVALID, WVALID, BREADY, BVALID, busy);
  end

  initial begin
      ARESETn=0; start=0; fault_mode=0;
      repeat (2) @(negedge ACLK);
      ARESETn=1;
      @(negedge ACLK);

      // kick off one write transaction
      $display("\n--- start one legal write ---");
      start=1;
      @(negedge ACLK);
      start=0;                    // start is a one-cycle pulse

      // let the transaction run to completion
      wait (!busy);               // busy drops when back in IDLE
      @(negedge ACLK);

      $display("\n--- transaction complete @ %0t ---", $time);
      repeat (2) @(negedge ACLK);
      $finish;
  end

endmodule