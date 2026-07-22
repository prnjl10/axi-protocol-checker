`timescale 1ns/1ns

import axi_checker_pkg::*;

module tb_csr;

  logic ACLK, ARESETn;

  // AXI4-Lite master-side signals (we drive these)
  logic        S_AWVALID; logic [31:0] S_AWADDR;  logic S_AWREADY;
  logic        S_WVALID;  logic [31:0] S_WDATA;   logic [3:0] S_WSTRB; logic S_WREADY;
  logic        S_BVALID;  logic [1:0]  S_BRESP;   logic S_BREADY;
  logic        S_ARVALID; logic [31:0] S_ARADDR;  logic S_ARREADY;
  logic        S_RVALID;  logic [31:0] S_RDATA;   logic [1:0] S_RRESP; logic S_RREADY;

  // CSR <-> system
  logic        start;
  logic [3:0]  fault_mode;
  logic        busy;
  logic [31:0] fifo_ts;
  logic [N_VIOL-1:0] fifo_viol;
  logic        fifo_empty, fifo_full, fifo_overflow;
  logic [15:0] fifo_count;
  logic        fifo_rd_en;

  initial ACLK = 0;
  always #5 ACLK = ~ACLK;

  // ---- DUT ----
  axi_lite_csr #(.ADDR_W(32), .TS_W(32)) u_csr (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .S_AWVALID(S_AWVALID), .S_AWADDR(S_AWADDR), .S_AWREADY(S_AWREADY),
      .S_WVALID(S_WVALID),   .S_WDATA(S_WDATA),   .S_WSTRB(S_WSTRB), .S_WREADY(S_WREADY),
      .S_BVALID(S_BVALID),   .S_BRESP(S_BRESP),   .S_BREADY(S_BREADY),
      .S_ARVALID(S_ARVALID), .S_ARADDR(S_ARADDR), .S_ARREADY(S_ARREADY),
      .S_RVALID(S_RVALID),   .S_RDATA(S_RDATA),   .S_RRESP(S_RRESP), .S_RREADY(S_RREADY),
      .start(start), .fault_mode(fault_mode), .busy(busy),
      .fifo_ts(fifo_ts), .fifo_viol(fifo_viol),
      .fifo_empty(fifo_empty), .fifo_full(fifo_full),
      .fifo_overflow(fifo_overflow), .fifo_count(fifo_count),
      .fifo_rd_en(fifo_rd_en)
  );

  // ---- fake FIFO/system status so reads return known values ----
  assign fifo_ts       = 32'h0000_1234;
  assign fifo_viol     = 15'b000_0000_0000_0101;  // C01_AW + C01_B set
  assign fifo_empty    = 1'b0;
  assign fifo_full     = 1'b0;
  assign fifo_overflow = 1'b1;
  assign fifo_count    = 16'd7;
  assign busy          = 1'b1;

  // ============================================================
  // AXI4-Lite master model: what the PS does, as tasks
  // ============================================================
  task axi_write(input [31:0] addr, input [31:0] data);
      @(negedge ACLK);
      S_AWVALID = 1; S_AWADDR = addr;
      // wait for address accepted
      while (!(S_AWVALID && S_AWREADY)) @(negedge ACLK);
      @(negedge ACLK);
      S_AWVALID = 0;
      S_WVALID = 1; S_WDATA = data; S_WSTRB = 4'hF;
      while (!(S_WVALID && S_WREADY)) @(negedge ACLK);
      @(negedge ACLK);
      S_WVALID = 0;
      S_BREADY = 1;
      while (!(S_BVALID && S_BREADY)) @(negedge ACLK);
      @(negedge ACLK);
      S_BREADY = 0;
      $display("  WRITE 0x%02h <= 0x%08h  (BRESP=%0d)", addr, data, S_BRESP);
  endtask

  task axi_read(input [31:0] addr, output [31:0] data);
      @(negedge ACLK);
      S_ARVALID = 1; S_ARADDR = addr;
      while (!(S_ARVALID && S_ARREADY)) @(negedge ACLK);
      @(negedge ACLK);
      S_ARVALID = 0;
      S_RREADY = 1;
      while (!(S_RVALID && S_RREADY)) @(negedge ACLK);
      data = S_RDATA;
      @(negedge ACLK);
      S_RREADY = 0;
      $display("  READ  0x%02h => 0x%08h  (RRESP=%0d)", addr, data, S_RRESP);
  endtask

  logic [31:0] rdata;

  initial begin
      ARESETn = 0;
      S_AWVALID=0; S_AWADDR=0; S_WVALID=0; S_WDATA=0; S_WSTRB=0; S_BREADY=0;
      S_ARVALID=0; S_ARADDR=0; S_RREADY=0;
      repeat (3) @(negedge ACLK);
      ARESETn = 1;
      @(negedge ACLK);

      $display("\n--- 1. write CTRL: fault_mode=5, start=1 ---");
      axi_write(32'h00, 32'h0000_0051);   // bits[7:4]=5, bit0=1
      $display("  -> start pulse=%b, fault_mode=%0d", start, fault_mode);

      $display("\n--- 2. read back CTRL ---");
      axi_read(32'h00, rdata);

      $display("\n--- 3. read STATUS (expect empty=0 full=0 ovf=1 busy=1) ---");
      axi_read(32'h04, rdata);
      $display("  -> empty=%b full=%b overflow=%b busy=%b",
               rdata[0], rdata[1], rdata[2], rdata[3]);

      $display("\n--- 4. read COUNT (expect 7) ---");
      axi_read(32'h08, rdata);

      $display("\n--- 5. read EV_TS (expect 0x1234) ---");
      axi_read(32'h0C, rdata);

      $display("\n--- 6. read EV_VIOL (expect 0x5) ---");
      axi_read(32'h10, rdata);

      $display("\n--- 7. write EV_POP -> expect fifo_rd_en pulse ---");
      fork
          axi_write(32'h14, 32'h1);
          begin
              // watch for the pop pulse
              @(posedge fifo_rd_en);
              $display("  -> fifo_rd_en pulsed at %0t", $time);
          end
      join

      $display("\n--- done @ %0t ---", $time);
      repeat (2) @(negedge ACLK);
      $finish;
  end

endmodule