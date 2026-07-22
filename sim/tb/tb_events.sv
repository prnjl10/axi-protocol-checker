`timescale 1ns/1ns

import axi_checker_pkg::*;

module tb_events;

  localparam int ADDR_W = 32;
  localparam int DATA_W = 32;

  logic ACLK, ARESETn;
  logic start;  logic [3:0] fault_mode;

  logic AWVALID; logic [ADDR_W-1:0] AWADDR; logic AWREADY;
  logic WVALID;  logic [DATA_W-1:0] WDATA;  logic WREADY;
  logic BVALID;  logic [1:0] BRESP;         logic BREADY;
  logic busy;

  logic ARVALID = 0, ARREADY = 0, RVALID = 0, RREADY = 0;
  logic [ADDR_W-1:0] ARADDR = 0;
  logic [1:0] RRESP = 0;

  logic [N_VIOL-1:0] violations;
  logic              viol_any;

  // FIFO read side
  logic                rd_en;
  logic [31:0]         rd_timestamp;
  logic [N_VIOL-1:0]   rd_violations;
  logic                empty, full, overflow;
  logic [15:0]         event_count;

  initial ACLK = 0;
  always #5 ACLK = ~ACLK;

  // ---- rogue master ----
  rogue_master #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_master (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .start(start), .fault_mode(fault_mode),
      .AWVALID(AWVALID), .AWADDR(AWADDR), .AWREADY(AWREADY),
      .WVALID(WVALID),   .WDATA(WDATA),   .WREADY(WREADY),
      .BVALID(BVALID),   .BRESP(BRESP),   .BREADY(BREADY),
      .busy(busy)
  );

  // ---- checker core (read-only tap) ----
  axi_checker_core #(.ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_core (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .AWVALID(AWVALID), .AWREADY(AWREADY), .AWADDR(AWADDR),
      .WVALID(WVALID),   .WREADY(WREADY),   .WDATA(WDATA),
      .BVALID(BVALID),   .BREADY(BREADY),   .BRESP(BRESP),
      .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR),
      .RVALID(RVALID),   .RREADY(RREADY),   .RRESP(RRESP),
      .violations(violations), .viol_any(viol_any)
  );

  // ---- event FIFO ----
  axi_event_fifo #(.DEPTH_LOG2(6), .TS_W(32)) u_fifo (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .violations(violations),
      .rd_en(rd_en),
      .rd_timestamp(rd_timestamp),
      .rd_violations(rd_violations),
      .empty(empty), .full(full),
      .event_count(event_count), .overflow(overflow)
  );

  // ---- delayed-ready slave (2-cycle stall) ----
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

  // ---- decoder ----
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

  // ---- run one transaction ----
  task run_txn(input logic [3:0] mode, input string label);
      $display("\n--- %s (fault_mode=%0d) ---", label, mode);
      fault_mode = mode; start = 1;
      @(negedge ACLK); start = 0;
      fork
          begin wait (!busy); end
          begin repeat (40) @(negedge ACLK); end
      join_any
      disable fork;
      repeat (3) @(negedge ACLK);
  endtask

  // ---- drain the FIFO and print every event ----
  // NOTE: the FIFO presents data combinationally at rd_ptr, so we READ FIRST,
  // then pulse rd_en to acknowledge and advance. Popping before reading yields
  // a phantom entry from an unwritten slot.
  task drain_fifo;
      int n;
      n = 0;
      $display("\n========== DRAINING EVENT FIFO ==========");
      $display("events buffered: %0d   overflow: %b", event_count, overflow);
      while (!empty) begin
          n++;
          // 1. read what is at the head (already valid)
          $write("EVENT %0d  ts=%0d  ->", n, rd_timestamp);
          for (int i = 0; i < N_VIOL; i++)
              if (rd_violations[i]) $write("  %s", viol_name(i));
          $write("\n");
          // 2. then acknowledge / advance
          rd_en = 1;
          @(negedge ACLK);
          rd_en = 0;
      end
      $display("========== %0d events total ==========", n);
  endtask

  initial begin
      ARESETn = 0; start = 0; fault_mode = 0; rd_en = 0;
      repeat (2) @(negedge ACLK);
      ARESETn = 1;
      @(negedge ACLK);

      run_txn(4'd0, "LEGAL write");
      run_txn(4'd1, "C01 on AW");
      run_txn(4'd2, "C02 on AW");
      run_txn(4'd3, "C01 on W");
      run_txn(4'd4, "C02 on W");
      run_txn(4'd5, "C09 misaligned");

      drain_fifo;

      $display("\n--- done @ %0t ---", $time);
      $finish;
  end

endmodule