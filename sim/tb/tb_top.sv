`timescale 1ns/1ns

import axi_checker_pkg::*;

// System-level test: drives ONLY the AXI4-Lite slave port, like the PS.
// This is a direct model of what the Python driver will do.
module tb_top;

  logic ACLK, ARESETn;

  logic        AWVALID; logic [31:0] AWADDR; logic AWREADY;
  logic        WVALID;  logic [31:0] WDATA;  logic [3:0] WSTRB; logic WREADY;
  logic        BVALID;  logic [1:0]  BRESP;  logic BREADY;
  logic        ARVALID; logic [31:0] ARADDR; logic ARREADY;
  logic        RVALID;  logic [31:0] RDATA;  logic [1:0] RRESP; logic RREADY;
  logic        viol_any_o;

  initial ACLK = 0;
  always #5 ACLK = ~ACLK;

  axi_checker_top #(.ADDR_W(32), .DATA_W(32)) dut (
      .ACLK(ACLK), .ARESETn(ARESETn),
      .S_AXI_AWVALID(AWVALID), .S_AXI_AWADDR(AWADDR), .S_AXI_AWREADY(AWREADY),
      .S_AXI_WVALID(WVALID),   .S_AXI_WDATA(WDATA),   .S_AXI_WSTRB(WSTRB),
      .S_AXI_WREADY(WREADY),
      .S_AXI_BVALID(BVALID),   .S_AXI_BRESP(BRESP),   .S_AXI_BREADY(BREADY),
      .S_AXI_ARVALID(ARVALID), .S_AXI_ARADDR(ARADDR), .S_AXI_ARREADY(ARREADY),
      .S_AXI_RVALID(RVALID),   .S_AXI_RDATA(RDATA),   .S_AXI_RRESP(RRESP),
      .S_AXI_RREADY(RREADY),
      .viol_any_o(viol_any_o)
  );

  // ---- AXI4-Lite master model (what the PS does) ----
  task axi_write(input [31:0] addr, input [31:0] data);
      @(negedge ACLK);
      AWVALID = 1; AWADDR = addr;
      while (!(AWVALID && AWREADY)) @(negedge ACLK);
      @(negedge ACLK); AWVALID = 0;
      WVALID = 1; WDATA = data; WSTRB = 4'hF;
      while (!(WVALID && WREADY)) @(negedge ACLK);
      @(negedge ACLK); WVALID = 0;
      BREADY = 1;
      while (!(BVALID && BREADY)) @(negedge ACLK);
      @(negedge ACLK); BREADY = 0;
  endtask

  task axi_read(input [31:0] addr, output [31:0] data);
      @(negedge ACLK);
      ARVALID = 1; ARADDR = addr;
      while (!(ARVALID && ARREADY)) @(negedge ACLK);
      @(negedge ACLK); ARVALID = 0;
      RREADY = 1;
      while (!(RVALID && RREADY)) @(negedge ACLK);
      data = RDATA;
      @(negedge ACLK); RREADY = 0;
  endtask

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

  logic [31:0] d, ts, viol, status, cnt;

  // run one transaction with a fault mode, via CSR only
  task run_fault(input int mode, input string label);
      $display("\n--- %s (mode=%0d) ---", label, mode);
      axi_write(32'h00, (mode << 4) | 32'h1);   // fault_mode + start
      // poll STATUS until busy clears (or give up)
      for (int i = 0; i < 60; i++) begin
          axi_read(32'h04, status);
          if (!status[3]) break;                 // bit3 = busy
      end
  endtask

  initial begin
      ARESETn = 0;
      AWVALID=0; AWADDR=0; WVALID=0; WDATA=0; WSTRB=0; BREADY=0;
      ARVALID=0; ARADDR=0; RREADY=0;
      repeat (3) @(negedge ACLK);
      ARESETn = 1;
      repeat (2) @(negedge ACLK);

      run_fault(0, "LEGAL write");
      run_fault(1, "C01 on AW");
      run_fault(4, "C02 on W");
      run_fault(5, "C09 misaligned");

      // ---- drain the FIFO through the CSR ----
      $display("\n========== DRAIN VIA CSR ==========");
      axi_read(32'h08, cnt);
      $display("events buffered: %0d", cnt);

      for (int n = 1; n <= cnt; n++) begin
          axi_read(32'h0C, ts);        // EV_TS
          axi_read(32'h10, viol);      // EV_VIOL
          $write("EVENT %0d  ts=%0d ->", n, ts);
          for (int i = 0; i < N_VIOL; i++)
              if (viol[i]) $write("  %s", viol_name(i));
          $write("\n");
          axi_write(32'h14, 32'h1);    // EV_POP
      end

      axi_read(32'h04, status);
      $display("final: empty=%b overflow=%b", status[0], status[2]);
      $display("\n--- done @ %0t ---", $time);
      $finish;
  end

endmodule