`include "uvm_macros.svh"
import uvm_pkg::*;

interface fifo_if(input logic clk);
  logic        reset;
  logic        w_enb;
  logic        r_enb;
  logic [15:0] din;
  logic [15:0] dout;
  logic        full;
  logic        empty;
endinterface

class fifo_seq_item extends uvm_sequence_item;
  `uvm_object_utils(fifo_seq_item)

  rand bit        w_enb;
  rand bit        r_enb;
  rand bit [15:0] din;
  bit [15:0]      dout;
  bit             full;
  bit             empty;

  constraint valid_op_c {
    (w_enb || r_enb);
  }

  function new(string name = "fifo_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("w_enb=%b r_enb=%b din=0x%0h dout=0x%0h full=%b empty=%b",
                     w_enb, r_enb, din, dout, full, empty);
  endfunction
endclass

class fifo_base_sequence extends uvm_sequence #(fifo_seq_item);
  `uvm_object_utils(fifo_base_sequence)

  function new(string name = "fifo_base_sequence");
    super.new(name);
  endfunction

  task body();
    fifo_seq_item req;

    repeat (8) begin
      req = fifo_seq_item::type_id::create("req");
      start_item(req);
      assert(req.randomize() with { w_enb == 1; r_enb == 0; });
      finish_item(req);
    end

    repeat (2) begin
      req = fifo_seq_item::type_id::create("req");
      start_item(req);
      assert(req.randomize() with { w_enb == 1; r_enb == 0; });
      finish_item(req);
    end

    repeat (8) begin
      req = fifo_seq_item::type_id::create("req");
      start_item(req);
      assert(req.randomize() with { w_enb == 0; r_enb == 1; });
      finish_item(req);
    end

    repeat (2) begin
      req = fifo_seq_item::type_id::create("req");
      start_item(req);
      assert(req.randomize() with { w_enb == 0; r_enb == 1; });
      finish_item(req);
    end

    repeat (10) begin
      req = fifo_seq_item::type_id::create("req");
      start_item(req);
      assert(req.randomize());
      finish_item(req);
    end

    req = fifo_seq_item::type_id::create("req");
    start_item(req);
    req.w_enb = 0;
    req.r_enb = 0;
    req.din   = 0;
    finish_item(req);
  endtask
endclass

typedef uvm_sequencer #(fifo_seq_item) fifo_sequencer;

class fifo_driver extends uvm_driver #(fifo_seq_item);
  `uvm_component_utils(fifo_driver)

  virtual fifo_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    vif.w_enb <= 0;
    vif.r_enb <= 0;
    vif.din   <= 0;

    @(negedge vif.reset);

    forever begin
      seq_item_port.get_next_item(req);

      @(negedge vif.clk);
      vif.w_enb <= req.w_enb;
      vif.r_enb <= req.r_enb;
      vif.din   <= req.din;

      seq_item_port.item_done();
      `uvm_info(get_type_name(), $sformatf("Drove: %s", req.convert2string()), UVM_HIGH)
    end
  endtask
endclass

class fifo_monitor extends uvm_monitor;
  `uvm_component_utils(fifo_monitor)

  virtual fifo_if vif;
  uvm_analysis_port #(fifo_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual fifo_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    fifo_seq_item tr;

    @(negedge vif.reset);

    forever begin
      @(posedge vif.clk);
      #1;
      if (vif.reset) continue;

      if (vif.w_enb || vif.r_enb) begin
        tr = fifo_seq_item::type_id::create("tr");
        tr.w_enb = vif.w_enb;
        tr.r_enb = vif.r_enb;
        tr.din   = vif.din;
        tr.dout  = vif.dout;
        tr.full  = vif.full;
        tr.empty = vif.empty;

        `uvm_info(get_type_name(), $sformatf("Sampled: %s", tr.convert2string()), UVM_HIGH)
        ap.write(tr);
      end
    end
  endtask
endclass

class fifo_agent extends uvm_agent;
  `uvm_component_utils(fifo_agent)

  fifo_driver    drv;
  fifo_monitor   mon;
  fifo_sequencer seqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = fifo_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      drv  = fifo_driver::type_id::create("drv", this);
      seqr = fifo_sequencer::type_id::create("seqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      drv.seq_item_port.connect(seqr.seq_item_export);
    end
  endfunction
endclass

`uvm_analysis_imp_decl(_mon)

class fifo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fifo_scoreboard)

  uvm_analysis_imp_mon #(fifo_seq_item, fifo_scoreboard) mon_imp;

  bit [15:0] ref_fifo[$];
  int pass_count;
  int fail_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon_imp = new("mon_imp", this);
  endfunction

  function void write_mon(fifo_seq_item tr);
    bit [15:0] exp_data;
    bit can_read  = tr.r_enb && (ref_fifo.size() > 0);
    bit can_write = tr.w_enb && (ref_fifo.size() < 8);

    if (can_read) begin
      exp_data = ref_fifo.pop_front();
      if (tr.dout === exp_data) begin
        pass_count++;
        `uvm_info(get_type_name(), $sformatf("Match: dout=0x%0h exp=0x%0h", tr.dout, exp_data), UVM_HIGH)
      end else begin
        fail_count++;
        `uvm_error(get_type_name(), $sformatf("Mismatch: dout=0x%0h exp=0x%0h", tr.dout, exp_data))
      end
    end

    if (can_write) begin
      ref_fifo.push_back(tr.din);
    end

    if (tr.full !== (ref_fifo.size() == 8)) begin
      fail_count++;
      `uvm_error(get_type_name(), $sformatf("Full flag error: actual=%b expected=%b (size=%0d)",
                 tr.full, (ref_fifo.size() == 8), ref_fifo.size()))
    end

    if (tr.empty !== (ref_fifo.size() == 0)) begin
      fail_count++;
      `uvm_error(get_type_name(), $sformatf("Empty flag error: actual=%b expected=%b (size=%0d)",
                 tr.empty, (ref_fifo.size() == 0), ref_fifo.size()))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf("Scoreboard complete. Matches: %0d, Mismatches: %0d", pass_count, fail_count), UVM_LOW)
    if (fail_count > 0)
      `uvm_error(get_type_name(), "Test failed due to mismatch errors")
  endfunction
endclass

class fifo_env extends uvm_env;
  `uvm_component_utils(fifo_env)

  fifo_agent      agt;
  fifo_scoreboard scb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agt = fifo_agent::type_id::create("agt", this);
    scb = fifo_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agt.mon.ap.connect(scb.mon_imp);
  endfunction
endclass

class fifo_base_test extends uvm_test;
  `uvm_component_utils(fifo_base_test)

  fifo_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = fifo_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    fifo_base_sequence seq;

    phase.raise_objection(this);

    seq = fifo_base_sequence::type_id::create("seq");
    seq.start(env.agt.seqr);

    #100;
    phase.drop_objection(this);
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

  initial begin
    intf.reset = 1;
    intf.w_enb = 0;
    intf.r_enb = 0;
    intf.din   = 0;
    #20;
    intf.reset = 0;
  end

  initial begin
    uvm_config_db #(virtual fifo_if)::set(null, "*", "vif", intf);
    run_test("fifo_base_test");
  end
endmodule
