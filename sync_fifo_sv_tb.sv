`timescale 1ns / 1ps

interface fifo_if(input logic clk);
  logic        reset;
  logic        w_enb;
  logic        r_enb;
  logic [15:0] din;
  logic [15:0] dout;
  logic        full;
  logic        empty;
endinterface

class transaction;
  rand bit        w_enb;
  rand bit        r_enb;
  rand bit [15:0] din;
  bit [15:0]      dout;
  bit             full;
  bit             empty;

  constraint valid_op {
    w_enb || r_enb;
  }
endclass

class generator;
  mailbox #(transaction) gen2drv;
  event drv_done;
  int num_trans;

  function new(mailbox #(transaction) gen2drv, event drv_done, int num_trans = 15);
    this.gen2drv   = gen2drv;
    this.drv_done  = drv_done;
    this.num_trans = num_trans;
  endfunction

  task run();
    transaction tr;

    $display("Test 1: Writing 8 items to fill FIFO");
    repeat (8) begin
      tr = new();
      assert(tr.randomize() with { w_enb == 1; r_enb == 0; });
      gen2drv.put(tr);
      @(drv_done);
    end

    $display("Test 2: Overflow test (writing to full FIFO)");
    repeat (2) begin
      tr = new();
      assert(tr.randomize() with { w_enb == 1; r_enb == 0; });
      gen2drv.put(tr);
      @(drv_done);
    end

    $display("Test 3: Reading 8 items to empty FIFO");
    repeat (8) begin
      tr = new();
      assert(tr.randomize() with { w_enb == 0; r_enb == 1; });
      gen2drv.put(tr);
      @(drv_done);
    end

    $display("Test 4: Underflow test (reading from empty FIFO)");
    repeat (2) begin
      tr = new();
      assert(tr.randomize() with { w_enb == 0; r_enb == 1; });
      gen2drv.put(tr);
      @(drv_done);
    end

    $display("Test 5: Random concurrent read and write operations");
    repeat (num_trans) begin
      tr = new();
      assert(tr.randomize());
      gen2drv.put(tr);
      @(drv_done);
    end

    tr = new();
    tr.w_enb = 0;
    tr.r_enb = 0;
    tr.din   = 0;
    gen2drv.put(tr);
    @(drv_done);
  endtask
endclass

class driver;
  virtual fifo_if vif;
  mailbox #(transaction) gen2drv;
  event drv_done;

  function new(virtual fifo_if vif, mailbox #(transaction) gen2drv, event drv_done);
    this.vif      = vif;
    this.gen2drv  = gen2drv;
    this.drv_done = drv_done;
  endfunction

  task run();
    transaction tr;
    vif.w_enb <= 0;
    vif.r_enb <= 0;
    vif.din   <= 0;

    wait(vif.reset == 0);

    forever begin
      gen2drv.get(tr);

      @(negedge vif.clk);
      vif.w_enb <= tr.w_enb;
      vif.r_enb <= tr.r_enb;
      vif.din   <= tr.din;

      ->drv_done;
    end
  endtask
endclass

class monitor;
  virtual fifo_if vif;
  mailbox #(transaction) mon2scb;

  function new(virtual fifo_if vif, mailbox #(transaction) mon2scb);
    this.vif     = vif;
    this.mon2scb = mon2scb;
  endfunction

  task run();
    transaction tr;

    wait(vif.reset == 0);

    forever begin
      @(posedge vif.clk);
      #1;

      if (vif.reset) continue;

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

class scoreboard;
  mailbox #(transaction) mon2scb;
  bit [15:0] ref_fifo[$];
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

      if (can_read) begin
        exp_data = ref_fifo.pop_front();
        if (tr.dout === exp_data) begin
          pass_count++;
          $display("[SCB] MATCH: dout = 0x%0h (exp = 0x%0h)", tr.dout, exp_data);
        end else begin
          fail_count++;
          $display("[SCB] MISMATCH: dout = 0x%0h, exp = 0x%0h", tr.dout, exp_data);
        end
      end

      if (can_write) begin
        ref_fifo.push_back(tr.din);
      end

      if (tr.full !== (ref_fifo.size() == 8)) begin
        fail_count++;
        $display("[SCB] ERROR: full flag actual=%0b, exp=%0b", tr.full, (ref_fifo.size() == 8));
      end

      if (tr.empty !== (ref_fifo.size() == 0)) begin
        fail_count++;
        $display("[SCB] ERROR: empty flag actual=%0b, exp=%0b", tr.empty, (ref_fifo.size() == 0));
      end
    end
  endtask

  function void report();
    $display("\n--- SCOREBOARD SUMMARY ---");
    $display("Matches: %0d | Errors: %0d", pass_count, fail_count);
    if (fail_count == 0 && pass_count > 0)
      $display("Status: PASSED\n");
    else
      $display("Status: FAILED\n");
  endfunction
endclass

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
    join_any

    #100;
    scb.report();
    $finish;
  endtask
endclass

module tb_top;
  bit clk;
  always #5 clk = ~clk;

  fifo_if intf(clk);

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

  initial begin
    intf.reset = 1;
    intf.w_enb = 0;
    intf.r_enb = 0;
    intf.din   = 0;
    #20;
    intf.reset = 0;
  end

  initial begin
    env = new(intf);
    env.run();
  end
endmodule
