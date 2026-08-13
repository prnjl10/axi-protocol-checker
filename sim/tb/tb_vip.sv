`timescale 1ns/1ns

import axi_checker_pkg::*;

// Independent-oracle cross-check.
//
// Three things observe the SAME nets driven by the rogue master:
//   1. the dummy slave (responds to traffic)
//   2. axi_checker_core   - your checker
//   3. axi_vip_axi4pc     - ARM's protocol checker (all ports are inputs)
//
// axi_vip_axi4pc is a SystemVerilog interface containing assertions. It drives
// nothing, so it sits alongside the existing testbench without altering it.
// PROTOCOL = 2 selects AXI4-Lite, enabling the Lite-specific assertions.
module tb_vip;

  localparam int ADDR_W = 32;
  localparam int DATA_W = 32;

  logic ACLK, ARESETn;
  logic start;  logic [3:0] fault_mode;

  logic AWVALID; logic [ADDR_W-1:0] AWADDR; logic AWREADY;
  logic WVALID;  logic [DATA_W-1:0] WDATA;  logic WREADY;
  logic BVALID;  logic [1:0] BRESP;         logic BREADY;
  logic busy;

  // read channel unused in v1 - held idle
  logic ARVALID = 0, ARREADY = 0, RVALID = 0, RREADY = 0;
  logic [ADDR_W-1:0] ARADDR = 0;
  logic [DATA_W-1:0] RDATA  = 0;
  logic [1:0] RRESP = 0;

  logic [N_VIOL-1:0] violations;
  logic              viol_any;

  initial ACLK = 0;
  always #5 ACLK = ~ACLK;

  // ============================================================
  // Rogue master - the fault source
  // ============================================================
  rogue_master #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_master (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .start(start), .fault_mode(fault_mode),
      .AWVALID(AWVALID), .AWADDR(AWADDR), .AWREADY(AWREADY),
      .WVALID(WVALID),   .WDATA(WDATA),   .WREADY(WREADY),
      .BVALID(BVALID),   .BRESP(BRESP),   .BREADY(BREADY),
      .busy(busy)
  );

  // ============================================================
  // Dummy slave - 2-cycle stall so faults have a waiting window
  // ============================================================
  logic [1:0] aw_wait, w_wait;
  always_ff @(posedge ACLK) begin
      if (!ARESETn) begin
          aw_wait <= 0; w_wait <= 0; BVALID <= 0; BRESP <= 0;
      end else begin
          if (AWVALID && !AWREADY)      aw_wait <= aw_wait + 1;
          else if (AWVALID && AWREADY)  aw_wait <= 0;
          if (WVALID && !WREADY)        w_wait <= w_wait + 1;
          else if (WVALID && WREADY)    w_wait <= 0;
          if (WVALID && WREADY)         begin BVALID <= 1; BRESP <= 2'b00; end
          else if (BVALID && BREADY)    BVALID <= 0;
      end
  end
  assign AWREADY = AWVALID && (aw_wait >= 2);
  assign WREADY  = WVALID  && (w_wait  >= 2);

  // ============================================================
  // YOUR checker
  // ============================================================
  axi_checker_core #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_core (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .AWVALID(AWVALID), .AWREADY(AWREADY), .AWADDR(AWADDR),
      .WVALID(WVALID),   .WREADY(WREADY),   .WDATA(WDATA),
      .BVALID(BVALID),   .BREADY(BREADY),   .BRESP(BRESP),
      .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR),
      .RVALID(RVALID),   .RREADY(RREADY),   .RRESP(RRESP),
      .violations(violations), .viol_any(viol_any)
  );

  // ============================================================
  // ARM's checker (via Xilinx VIP) - inputs only, drives nothing.
  // Full-AXI4 signals are tied to the values AXI4-Lite implies:
  //   AxLEN=0 (single beat), AxSIZE=2 (4 bytes), AxBURST=1 (INCR),
  //   WLAST/RLAST=1 (every beat is the last), no IDs, no locking.
  // ============================================================
  axi_vip_axi4pc #(
      .WADDR_WIDTH (ADDR_W),
      .RADDR_WIDTH (ADDR_W),
      .WDATA_WIDTH (DATA_W),
      .RDATA_WIDTH (DATA_W),
      .PROTOCOL    (2),        // 3'b010 = AXI4-Lite
      .WID_WIDTH   (0),
      .RID_WIDTH   (0),
      .HAS_ARESETN (1)
  ) u_arm_pc (
      .ACLK     (ACLK),
      .ACLKEN   (1'b1),
      .ARESETn  (ARESETn),

      // write address channel
      .AWADDR   (AWADDR),
      .AWID     (1'b0),
      .AWLEN    (8'd0),
      .AWSIZE   (3'd2),
      .AWBURST  (2'b01),
      .AWLOCK   (1'b0),
      .AWCACHE  (4'b0000),
      .AWPROT   (3'b000),
      .AWVALID  (AWVALID),
      .AWREADY  (AWREADY),
      .AWUSER   (1'b1),
      .AWREGION (4'b0000),
      .AWQOS    (4'b0000),

      // write data channel
      .WLAST    (1'b1),
      .WDATA    (WDATA),
      .WSTRB    (4'hF),
      .WVALID   (WVALID),
      .WREADY   (WREADY),
      .WUSER    (1'b1),

      // write response channel
      .BRESP    (BRESP),
      .BID      (1'b0),
      .BVALID   (BVALID),
      .BREADY   (BREADY),
      .BUSER    (1'b1),

      // read address channel
      .ARADDR   (ARADDR),
      .ARID     (1'b0),
      .ARLEN    (8'd0),
      .ARSIZE   (3'd2),
      .ARBURST  (2'b01),
      .ARLOCK   (1'b0),
      .ARCACHE  (4'b0000),
      .ARPROT   (3'b000),
      .ARVALID  (ARVALID),
      .ARREADY  (ARREADY),
      .ARUSER   (1'b1),
      .ARREGION (4'b0000),
      .ARQOS    (4'b0000),

      // read data channel
      .RID      (1'b0),
      .RLAST    (1'b1),
      .RDATA    (RDATA),
      .RRESP    (RRESP),
      .RVALID   (RVALID),
      .RREADY   (RREADY),
      .RUSER    (1'b1),

      .CACTIVE  (1'b1),
      .CSYSREQ  (1'b1),
      .CSYSACK  (1'b1)
  );

  // ============================================================
  // Reporting - your checker
  // ============================================================
  function string viol_name(int idx);
      case (idx)
          V_C01_AW: return "C01 AW-retract";  V_C01_W:  return "C01 W-retract";
          V_C01_B:  return "C01 B-retract";   V_C01_AR: return "C01 AR-retract";
          V_C01_R:  return "C01 R-retract";   V_C02_AW: return "C02 AW-stable";
          V_C02_W:  return "C02 W-stable";    V_C02_B:  return "C02 B-stable";
          V_C02_AR: return "C02 AR-stable";   V_C02_R:  return "C02 R-stable";
          V_C03:    return "C03 reset";       V_C05:    return "C05 EXOKAY";
          V_C07:    return "C07 write-order"; V_C08:    return "C08 read-order";
          V_C09:    return "C09 align";       default:  return "unknown";
      endcase
  endfunction

  always_ff @(posedge ACLK) begin
      if (ARESETn && viol_any)
          for (int i = 0; i < N_VIOL; i++)
              if (violations[i])
                  $display("    >>> MINE: %s  @ %0t", viol_name(i), $time);
  end

  // ============================================================
  // Fault campaign
  // ============================================================
  task run_txn(input logic [3:0] mode, input string label);
      $display("\n========== %s (mode=%0d) ==========", label, mode);
      fault_mode = mode; start = 1;
      @(negedge ACLK); start = 0;
      fork
          begin wait (!busy); end
          begin repeat (40) @(negedge ACLK); end
      join_any
      disable fork;
      repeat (4) @(negedge ACLK);
  endtask

  initial begin
      ARESETn = 0; start = 0; fault_mode = 0;

      // ARM's checker calls $fatal on a violation, which would end the
      // simulation at the first fault. Downgrade to warnings so all six
      // fault modes run in one campaign.
      u_arm_pc.fatal_to_warnings = 1;

      repeat (3) @(negedge ACLK);
      ARESETn = 1;
      repeat (2) @(negedge ACLK);

      run_txn(4'd0, "MODE 0 - compliant write");
      run_txn(4'd1, "MODE 1 - AWVALID deasserted early");
      run_txn(4'd2, "MODE 2 - AWADDR changed while waiting");
      run_txn(4'd3, "MODE 3 - WVALID deasserted early");
      run_txn(4'd4, "MODE 4 - WDATA changed while waiting");
      run_txn(4'd5, "MODE 5 - AWADDR misaligned (0x42)");

      $display("\n========== campaign complete @ %0t ==========", $time);
      $finish;
  end

endmodule