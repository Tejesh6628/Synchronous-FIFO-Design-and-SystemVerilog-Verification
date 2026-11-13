// ============================================================================
//  SystemVerilog OOP Testbench for Synchronous FIFO
//  Architecture: Generator -> Driver -> DUT -> Monitor -> Scoreboard
// ============================================================================

`timescale 1ns / 1ps

// ─────────────────────────────────────────────────────────────────────────────
// 1. INTERFACE: Bundles all signals connecting Testbench to DUT
// ─────────────────────────────────────────────────────────────────────────────
interface fifo_if(input logic clk);
  logic        reset;
  logic        w_enb;
  logic        r_enb;
  logic [15:0] din;
  logic [15:0] dout;
  logic        full;
  logic        empty;
endinterface

// ─────────────────────────────────────────────────────────────────────────────
// 2. TRANSACTION: Holds data for a single operation
// ─────────────────────────────────────────────────────────────────────────────
class transaction;
  rand bit        w_enb;
  rand bit        r_enb;
  rand bit [15:0] din;
  bit [15:0]      dout;
  bit             full;
  bit             empty;

  // Ensure at least one operation (read or write) happens
  constraint valid_op {
    w_enb || r_enb;
  }

  function void display(string tag = "");
    $display("[%0t] %s | w_enb=%0b r_enb=%0b din=0x%04h | dout=0x%04h full=%0b empty=%0b",
             $time, tag, w_enb, r_enb, din, dout, full, empty);
  endfunction
endclass

// ─────────────────────────────────────────────────────────────────────────────
// 3. GENERATOR: Creates and randomizes transactions, sends via Mailbox
// ─────────────────────────────────────────────────────────────────────────────
class generator;
  mailbox #(transaction) gen2drv;
  event drv_done;
  int num_trans;

  function new(mailbox #(transaction) gen2drv, event drv_done, int num_trans = 20);
    this.gen2drv   = gen2drv;
    this.drv_done  = drv_done;
    this.num_trans = num_trans;
  endfunction

  task run();
    transaction tr;

    // Phase 1: Write 8 items to fill FIFO
    $display("\n[GEN] >>> Phase 1: Writing 8 items to fill FIFO");
    repeat (8) begin
      tr = new();
      assert(tr.randomize() with { w_enb == 1; r_enb == 0; });
      gen2drv.put(tr);
      @(drv_done);
    end

    // Phase 2: Attempt write when full (Overflow)
    $display("\n[GEN] >>> Phase 2: Overflow test (write when full)");
    repeat (2) begin
      tr = new();
      assert(tr.randomize() with { w_enb == 1; r_enb == 0; });
      gen2drv.put(tr);
      @(drv_done);
    end

    // Phase 3: Read 8 items to empty FIFO
    $display("\n[GEN] >>> Phase 3: Reading 8 items to empty FIFO");
    repeat (8) begin
      tr = new();
      assert(tr.randomize() with { w_enb == 0; r_enb == 1; });
      gen2drv.put(tr);
      @(drv_done);
    end

    // Phase 4: Attempt read when empty (Underflow)
    $display("\n[GEN] >>> Phase 4: Underflow test (read when empty)");
    repeat (2) begin
      tr = new();
      assert(tr.randomize() with { w_enb == 0; r_enb == 1; });
      gen2drv.put(tr);
      @(drv_done);
    end

    // Phase 5: Random simultaneous Read and Write
    $display("\n[GEN] >>> Phase 5: Random Read/Write operations");
    repeat (num_trans) begin
      tr = new();
      assert(tr.randomize());
      gen2drv.put(tr);
      @(drv_done);
    end

    // End of stimulus: clear control signals
    tr = new();
    tr.w_enb = 0; tr.r_enb = 0; tr.din = 0;
    gen2drv.put(tr);
    @(drv_done);
  endtask
endclass

// ─────────────────────────────────────────────────────────────────────────────
// 4. DRIVER: Receives transaction from mailbox and drives interface pins
// ─────────────────────────────────────────────────────────────────────────────
class driver;
  virtual fifo_if vif;
  mailbox #(transaction) gen2drv;
  event drv_done;

  function new(virtual fifo_if vif, mailbox #(transaction) gen2drv, event drv_done);
    this.vif     = vif;
    this.gen2drv = gen2drv;
    this.drv_done = drv_done;
  endfunction

  task run();
    transaction tr;
    vif.w_enb <= 0;
    vif.r_enb <= 0;
    vif.din   <= 0;

    @(negedge vif.reset);

    forever begin
      gen2drv.get(tr);

      // Drive at negedge clk to give 5ns clean setup time before posedge
      @(negedge vif.clk);
      vif.w_enb <= tr.w_enb;
      vif.r_enb <= tr.r_enb;
      vif.din   <= tr.din;

      ->drv_done;
    end
  endtask
endclass

// ─────────────────────────────────────────────────────────────────────────────
// 5. MONITOR: Passively samples interface pins and sends to Scoreboard
// ─────────────────────────────────────────────────────────────────────────────
class monitor;
  virtual fifo_if vif;
  mailbox #(transaction) mon2scb;

  function new(virtual fifo_if vif, mailbox #(transaction) mon2scb);
    this.vif     = vif;
    this.mon2scb = mon2scb;
  endfunction

  task run();
    transaction tr;

    @(negedge vif.reset);

    forever begin
      @(posedge vif.clk);
      #1; // Wait 1ns after clock edge for DUT outputs to settle

      if (vif.reset) continue;

      // Only forward active write or read operations to scoreboard
      if (vif.w_enb || vif.r_enb) begin
        tr = new();
        tr.w_enb = vif.w_enb;
        tr.r_enb = vif.r_enb;
        tr.din   = vif.din;
        tr.dout  = vif.dout;
        tr.full  = vif.full;
        tr.empty = vif.empty;

        mon2scb.put(tr);
      end
    end
  endtask
endclass

// ─────────────────────────────────────────────────────────────────────────────
// 6. SCOREBOARD: Checks DUT output against Golden Reference Model (Queue)
// ─────────────────────────────────────────────────────────────────────────────
class scoreboard;
  mailbox #(transaction) mon2scb;
  bit [15:0] ref_fifo[$]; // Unbounded queue mimicking ideal FIFO
  int pass_count = 0;
  int fail_count = 0;

  function new(mailbox #(transaction) mon2scb);
    this.mon2scb = mon2scb;
  endfunction

  task run();
    transaction tr;
    bit [15:0] exp_data;
    bit can_read, can_write;

    forever begin
      mon2scb.get(tr);

      can_read  = tr.r_enb && (ref_fifo.size() > 0);
      can_write = tr.w_enb && (ref_fifo.size() < 8);

      // Check Read Data
      if (can_read) begin
        exp_data = ref_fifo.pop_front();
        if (tr.dout === exp_data) begin
          pass_count++;
          $display("[SCB - PASS] Data Match: dout = 0x%04h (expected = 0x%04h)", tr.dout, exp_data);
        end else begin
          fail_count++;
          $display("[SCB - FAIL] Data Mismatch: dout = 0x%04h, expected = 0x%04h", tr.dout, exp_data);
        end
      end

      // Update Reference Model on Write
      if (can_write) begin
        ref_fifo.push_back(tr.din);
      end

      // Verify Full Flag
      if (tr.full !== (ref_fifo.size() == 8)) begin
        fail_count++;
        $display("[SCB - FAIL] Full Flag Error: actual=%0b, expected=%0b", tr.full, (ref_fifo.size() == 8));
      end

      // Verify Empty Flag
      if (tr.empty !== (ref_fifo.size() == 0)) begin
        fail_count++;
        $display("[SCB - FAIL] Empty Flag Error: actual=%0b, expected=%0b", tr.empty, (ref_fifo.size() == 0));
      end
    end
  endtask

  function void report();
    $display("\n==============================================");
    $display("           SCOREBOARD FINAL REPORT            ");
    $display("==============================================");
    $display(" Total Matches (PASSED): %0d", pass_count);
    $display(" Total Errors  (FAILED): %0d", fail_count);
    if (fail_count == 0 && pass_count > 0)
      $display(" RESULT: *** TEST PASSED SUCCESSFULLY ***");
    else
      $display(" RESULT: *** TEST FAILED ***");
    $display("==============================================\n");
  endfunction
endclass

// ─────────────────────────────────────────────────────────────────────────────
// 7. ENVIRONMENT: Encapsulates Generator, Driver, Monitor, and Scoreboard
// ─────────────────────────────────────────────────────────────────────────────
class environment;
  generator  gen;
  driver     drv;
  monitor    mon;
  scoreboard scb;

  mailbox #(transaction) gen2drv;
  mailbox #(transaction) mon2scb;
  event drv_done;

  virtual fifo_if vif;

  function new(virtual fifo_if vif);
    this.vif = vif;
    gen2drv = new();
    mon2scb = new();

    gen = new(gen2drv, drv_done, 15);
    drv = new(vif, gen2drv, drv_done);
    mon = new(vif, mon2scb);
    scb = new(mon2scb);
  endfunction

  task run();
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join_any // Stop when generator finishes stimulus

    #100; // Drain time
    scb.report();
    $finish;
  endtask
endclass

// ─────────────────────────────────────────────────────────────────────────────
// 8. TOP MODULE: Clock, Reset, DUT, and Testbench Launcher
// ─────────────────────────────────────────────────────────────────────────────
module tb_top;
  bit clk;
  always #5 clk = ~clk; // 100 MHz clock

  // Instantiate Interface
  fifo_if intf(clk);

  // Instantiate DUT
  sync_fifo #(.Depth(8), .Width(16)) dut (
    .clk   (clk),
    .reset (intf.reset),
    .w_enb (intf.w_enb),
    .r_enb (intf.r_enb),
    .din   (intf.din),
    .dout  (intf.dout),
    .full  (intf.full),
    .empty (intf.empty)
  );

  environment env;

  // Reset sequence and start simulation
  initial begin
    intf.reset = 1;
    intf.w_enb = 0;
    intf.r_enb = 0;
    intf.din   = 0;
    #20;
    intf.reset = 0;

    env = new(intf);
    env.run();
  end
endmodule
