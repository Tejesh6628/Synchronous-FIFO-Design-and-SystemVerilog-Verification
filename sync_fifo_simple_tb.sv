//==============================================================================
// Project     : Synchronous FIFO Design & Verification
// File        : sync_fifo_simple_tb.sv
// Description : Simple, Clean SystemVerilog OOP Testbench (Interview Friendly)
//==============================================================================

`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// 1. INTERFACE
//------------------------------------------------------------------------------
interface fifo_if #(parameter WIDTH = 16);
  logic             clk;
  logic             reset;
  logic             w_enb;
  logic             r_enb;
  logic [WIDTH-1:0] din;
  logic [WIDTH-1:0] dout;
  logic             full;
  logic             empty;
endinterface


//------------------------------------------------------------------------------
// 2. TRANSACTION (Packet of data)
//------------------------------------------------------------------------------
class transaction #(parameter WIDTH = 16);
  rand bit [WIDTH-1:0] din;
  rand bit             w_enb;
  rand bit             r_enb;
  bit      [WIDTH-1:0] dout;
  bit                  full;
  bit                  empty;

  // Simple distribution: 40% write, 40% read, 20% both
  constraint c_rw {
    {w_enb, r_enb} dist {
      2'b10 := 40,
      2'b01 := 40,
      2'b11 := 20
    };
  }

  // Display method for debugging
  function void display(string tag);
    $display("[%0s] @ %0t | w_enb=%0b r_enb=%0b din=0x%04h dout=0x%04h | full=%0b empty=%0b",
             tag, $time, w_enb, r_enb, din, dout, full, empty);
  endfunction

  // Deep copy method
  function transaction #(WIDTH) copy();
    copy = new();
    copy.din   = this.din;
    copy.w_enb = this.w_enb;
    copy.r_enb = this.r_enb;
    copy.dout  = this.dout;
    copy.full  = this.full;
    copy.empty = this.empty;
  endfunction
endclass


//------------------------------------------------------------------------------
// 3. GENERATOR (Creates random transactions)
//------------------------------------------------------------------------------
class generator #(parameter WIDTH = 16);
  transaction #(WIDTH) tr;
  mailbox #(transaction #(WIDTH)) mbx; // Sends to Driver
  event next;                          // Handshake: wait for driver/scoreboard
  event done;                          // Indicates generation finished
  int count;                           // Number of stimulus items

  function new(mailbox #(transaction #(WIDTH)) mbx, int count);
    this.mbx   = mbx;
    this.count = count;
    tr = new();
  endfunction

  task run();
    repeat (count) begin
      assert(tr.randomize()) else $error("[GEN] Randomization failed!");
      mbx.put(tr.copy());
      tr.display("GEN");
      @(next); // Wait for the current transaction to be driven
    end
    ->done;
  endtask
endclass


//------------------------------------------------------------------------------
// 4. DRIVER (Wiggles physical pins on the interface)
//------------------------------------------------------------------------------
class driver #(parameter WIDTH = 16);
  virtual fifo_if #(WIDTH) vif;
  mailbox #(transaction #(WIDTH)) mbx;
  transaction #(WIDTH) tr;
  event next;

  function new(virtual fifo_if #(WIDTH) vif, mailbox #(transaction #(WIDTH)) mbx);
    this.vif = vif;
    this.mbx = mbx;
  endfunction

  // Reset Task
  task reset();
    vif.reset <= 1'b1;
    vif.w_enb <= 1'b0;
    vif.r_enb <= 1'b0;
    vif.din   <= '0;
    repeat (3) @(posedge vif.clk);
    vif.reset <= 1'b0;
    @(posedge vif.clk);
    $display("[DRV] Reset Completed Successfully.");
  endtask

  // Run Task: Drives pins synchronously
  task run();
    forever begin
      mbx.get(tr);
      @(posedge vif.clk);
      vif.w_enb <= tr.w_enb;
      vif.r_enb <= tr.r_enb;
      vif.din   <= tr.din;
      tr.display("DRV");
      ->next; // Tell generator to create the next item
    end
  endtask
endclass


//------------------------------------------------------------------------------
// 5. MONITOR (Passively captures DUT inputs & outputs)
//------------------------------------------------------------------------------
class monitor #(parameter WIDTH = 16);
  virtual fifo_if #(WIDTH) vif;
  mailbox #(transaction #(WIDTH)) mbx; // Sends to Scoreboard
  transaction #(WIDTH) tr;

  function new(virtual fifo_if #(WIDTH) vif, mailbox #(transaction #(WIDTH)) mbx);
    this.vif = vif;
    this.mbx = mbx;
  endfunction

  task run();
    forever begin
      @(posedge vif.clk);
      #1; // Sample shortly after clock edge to avoid race conditions
      tr = new();
      tr.w_enb = vif.w_enb;
      tr.r_enb = vif.r_enb;
      tr.din   = vif.din;
      tr.dout  = vif.dout;
      tr.full  = vif.full;
      tr.empty = vif.empty;
      tr.display("MON");
      mbx.put(tr);
    end
  endtask
endclass


//------------------------------------------------------------------------------
// 6. SCOREBOARD (Checks data integrity with a reference queue)
//------------------------------------------------------------------------------
class scoreboard #(parameter WIDTH = 16, parameter DEPTH = 8);
  mailbox #(transaction #(WIDTH)) mbx;
  transaction #(WIDTH) tr;

  bit [WIDTH-1:0] ref_queue[$]; // Golden reference FIFO queue
  bit [WIDTH-1:0] expected_dout;
  bit             check_dout = 0;

  int match = 0, mismatch = 0;

  function new(mailbox #(transaction #(WIDTH)) mbx);
    this.mbx = mbx;
  endfunction

  task run();
    forever begin
      mbx.get(tr);

      // 1. Check data from previous clock cycle's read (1-cycle sync latency)
      if (check_dout) begin
        if (tr.dout === expected_dout) begin
          $display("[SCO] ==> MATCH! dout=0x%04h (Expected: 0x%04h)", tr.dout, expected_dout);
          match++;
        end else begin
          $error("[SCO] ==> MISMATCH! dout=0x%04h (Expected: 0x%04h)", tr.dout, expected_dout);
          mismatch++;
        end
        check_dout = 0;
      end

      // 2. Check full & empty flags
      if (tr.full !== (ref_queue.size() == DEPTH))
        $error("[SCO] FULL flag mismatch! DUT=%0b Expected=%0b", tr.full, (ref_queue.size() == DEPTH));

      if (tr.empty !== (ref_queue.size() == 0))
        $error("[SCO] EMPTY flag mismatch! DUT=%0b Expected=%0b", tr.empty, (ref_queue.size() == 0));

      // 3. Model Read
      if (tr.r_enb && (ref_queue.size() != 0)) begin
        expected_dout = ref_queue.pop_front();
        check_dout    = 1; // Expect this value on the next clock
      end

      // 4. Model Write
      if (tr.w_enb && (ref_queue.size() != DEPTH)) begin
        ref_queue.push_back(tr.din);
        $display("[SCO] Stored in Ref Queue: 0x%04h (Count=%0d)", tr.din, ref_queue.size());
      end
    end
  endtask
endclass


//------------------------------------------------------------------------------
// 7. ENVIRONMENT (Packages Gen, Drv, Mon, Scb together)
//------------------------------------------------------------------------------
class environment #(parameter WIDTH = 16, parameter DEPTH = 8);
  generator  #(WIDTH)         gen;
  driver     #(WIDTH)         drv;
  monitor    #(WIDTH)         mon;
  scoreboard #(WIDTH, DEPTH) scb;

  mailbox #(transaction #(WIDTH)) gd_mbx; // Gen -> Drv mailbox
  mailbox #(transaction #(WIDTH)) ms_mbx; // Mon -> Scb mailbox
  event next;

  virtual fifo_if #(WIDTH) vif;

  function new(virtual fifo_if #(WIDTH) vif, int test_count = 50);
    this.vif = vif;
    gd_mbx   = new();
    ms_mbx   = new();

    gen = new(gd_mbx, test_count);
    drv = new(vif, gd_mbx);
    mon = new(vif, ms_mbx);
    scb = new(ms_mbx);

    // Connect event handshake between Gen and Drv
    gen.next = drv.next;
  endfunction

  task pre_test();
    drv.reset();
  endtask

  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join_any // Stops when generator finishes
  endtask

  task post_test();
    wait(gen.done.triggered);
    #100; // Allow final in-flight reads to settle
    $display("\n==============================================");
    $display("               TEST SUMMARY                   ");
    $display("  Total Matches    : %0d", scb.match);
    $display("  Total Mismatches : %0d", scb.mismatch);
    $display("==============================================");
    if (scb.mismatch == 0 && scb.match > 0)
      $display(" >>>>> TEST PASSED <<<<< \n");
    else
      $display(" >>>>> TEST FAILED <<<<< \n");
    $finish;
  endtask

  task run();
    pre_test();
    test();
    post_test();
  endtask
endclass


//------------------------------------------------------------------------------
// 8. TESTBENCH TOP (Instantiates DUT, Clock, and runs Environment)
//------------------------------------------------------------------------------
module tb;
  parameter DEPTH = 8;
  parameter WIDTH = 16;

  // Clock generation (100MHz)
  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  // Interface
  fifo_if #(WIDTH) intf ();
  assign intf.clk = clk;

  // Connect DUT (sync_fifo.v)
  sync_fifo #(
    .Depth(DEPTH),
    .Width(WIDTH)
  ) dut (
    .clk   (intf.clk),
    .reset (intf.reset),
    .w_enb (intf.w_enb),
    .r_enb (intf.r_enb),
    .din   (intf.din),
    .dout  (intf.dout),
    .full  (intf.full),
    .empty (intf.empty)
  );

  environment #(WIDTH, DEPTH) env;

  initial begin
    env = new(intf, 60); // Run 60 random operations
    env.run();
  end

  // Dump waveforms
  initial begin
    $dumpfile("fifo_simple.vcd");
    $dumpvars(0, tb);
  end
endmodule
