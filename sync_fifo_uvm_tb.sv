//==============================================================================
// Project      : Synchronous FIFO Design & Verification
// File         : sync_fifo_uvm_tb.sv
// Description  : Complete Self-Contained UVM 1.2 Testbench in a Single File
// Standard     : IEEE 1800-2017 SystemVerilog / Accellera UVM 1.2
// Parameters   : Depth = 8, Width = 16 (Configurable)
//==============================================================================

`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

//------------------------------------------------------------------------------
// 1. INTERFACE (fifo_if)
//------------------------------------------------------------------------------
// Bundles all signals connecting the UVM Testbench to the DUT.
// Clocking blocks prevent race conditions between Testbench (TB) and RTL.
//------------------------------------------------------------------------------
interface fifo_if #(parameter WIDTH = 16) (input logic clk);
  logic             reset;
  logic             w_enb;
  logic             r_enb;
  logic [WIDTH-1:0] din;
  logic [WIDTH-1:0] dout;
  logic             full;
  logic             empty;

  // Driver Clocking Block (skewed outputs to avoid hold violations)
  clocking drv_cb @(posedge clk);
    default input #1ns output #1ns;
    output reset;
    output w_enb;
    output r_enb;
    output din;
    input  dout;
    input  full;
    input  empty;
  endclocking

  // Monitor Clocking Block (samples inputs & outputs synchronously)
  clocking mon_cb @(posedge clk);
    default input #1ns output #1ns;
    input reset;
    input w_enb;
    input r_enb;
    input din;
    input dout;
    input full;
    input empty;
  endclocking

  // Modports
  modport DRV (clocking drv_cb, input clk);
  modport MON (clocking mon_cb, input clk);
endinterface : fifo_if


//------------------------------------------------------------------------------
// 2. SEQUENCE ITEM / TRANSACTION (fifo_seq_item)
//------------------------------------------------------------------------------
// Represents the fundamental stimulus unit passed between Sequencer, Driver,
// Monitor, and Scoreboard.
//------------------------------------------------------------------------------
class fifo_seq_item #(parameter WIDTH = 16) extends uvm_sequence_item;
  // Randomized stimulus fields (inputs to DUT)
  rand bit             w_enb;
  rand bit             r_enb;
  rand bit [WIDTH-1:0] din;

  // Response / Observation fields (sampled outputs from DUT)
  bit [WIDTH-1:0]      dout;
  bit                  full;
  bit                  empty;

  // Constraints: weighted distributions to exercise varied FIFO scenarios
  constraint c_oper_dist {
    // 40% write-only, 40% read-only, 20% simultaneous read-write
    {w_enb, r_enb} dist {
      2'b10 := 40,
      2'b01 := 40,
      2'b11 := 20
    };
  }

  // UVM Field Automation Macros (enables automatic print, copy, compare)
  `uvm_object_utils_begin(fifo_seq_item #(WIDTH))
    `uvm_field_int(w_enb, UVM_ALL_ON)
    `uvm_field_int(r_enb, UVM_ALL_ON)
    `uvm_field_int(din,   UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(dout,  UVM_ALL_ON | UVM_HEX)
    `uvm_field_int(full,  UVM_ALL_ON)
    `uvm_field_int(empty, UVM_ALL_ON)
  `uvm_object_utils_end

  // Constructor
  function new(string name = "fifo_seq_item");
    super.new(name);
  endfunction

  // Custom convert2string for human-readable logging
  virtual function string convert2string();
    return $sformatf("w_enb=%0b r_enb=%0b din=0x%04h dout=0x%04h full=%0b empty=%0b",
                     w_enb, r_enb, din, dout, full, empty);
  endfunction
endclass : fifo_seq_item


//------------------------------------------------------------------------------
// 3. SEQUENCES (Stimulus Scenarios)
//------------------------------------------------------------------------------
// Sequences define the intent of verification (Reset, Fill, Drain, Corner cases).
//------------------------------------------------------------------------------

// 3.1 Base Sequence
class fifo_base_seq #(parameter WIDTH = 16) extends uvm_sequence #(fifo_seq_item #(WIDTH));
  `uvm_object_utils(fifo_base_seq #(WIDTH))
  function new(string name = "fifo_base_seq");
    super.new(name);
  endfunction
endclass : fifo_base_seq

// 3.2 Write-Only Sequence (Fills FIFO up to full + tests overflow)
class fifo_write_seq #(parameter WIDTH = 16, parameter DEPTH = 8) extends fifo_base_seq #(WIDTH);
  `uvm_object_utils(fifo_write_seq #(WIDTH, DEPTH))
  function new(string name = "fifo_write_seq");
    super.new(name);
  endfunction

  virtual task body();
    fifo_seq_item #(WIDTH) req;
    `uvm_info(get_type_name(), "Executing FIFO Fill + Overflow Sequence", UVM_LOW)
    // Depth + 2 iterations to trigger overflow condition
    repeat (DEPTH + 2) begin
      req = fifo_seq_item #(WIDTH)::type_id::create("req");
      start_item(req);
      assert(req.randomize() with { w_enb == 1; r_enb == 0; });
      finish_item(req);
    end
  endtask
endclass : fifo_write_seq

// 3.3 Read-Only Sequence (Drains FIFO until empty + tests underflow)
class fifo_read_seq #(parameter WIDTH = 16, parameter DEPTH = 8) extends fifo_base_seq #(WIDTH);
  `uvm_object_utils(fifo_read_seq #(WIDTH, DEPTH))
  function new(string name = "fifo_read_seq");
    super.new(name);
  endfunction

  virtual task body();
    fifo_seq_item #(WIDTH) req;
    `uvm_info(get_type_name(), "Executing FIFO Drain + Underflow Sequence", UVM_LOW)
    // Depth + 2 iterations to trigger underflow condition
    repeat (DEPTH + 2) begin
      req = fifo_seq_item #(WIDTH)::type_id::create("req");
      start_item(req);
      assert(req.randomize() with { w_enb == 0; r_enb == 1; });
      finish_item(req);
    end
  endtask
endclass : fifo_read_seq

// 3.4 Simultaneous Read/Write Sequence
class fifo_simultaneous_seq #(parameter WIDTH = 16) extends fifo_base_seq #(WIDTH);
  `uvm_object_utils(fifo_simultaneous_seq #(WIDTH))
  function new(string name = "fifo_simultaneous_seq");
    super.new(name);
  endfunction

  virtual task body();
    fifo_seq_item #(WIDTH) req;
    `uvm_info(get_type_name(), "Executing Simultaneous Read-Write Sequence", UVM_LOW)
    repeat (10) begin
      req = fifo_seq_item #(WIDTH)::type_id::create("req");
      start_item(req);
      assert(req.randomize() with { w_enb == 1; r_enb == 1; });
      finish_item(req);
    end
  endtask
endclass : fifo_simultaneous_seq

// 3.5 Fully Constrained Random Stress Sequence
class fifo_random_stress_seq #(parameter WIDTH = 16) extends fifo_base_seq #(WIDTH);
  `uvm_object_utils(fifo_random_stress_seq #(WIDTH))
  function new(string name = "fifo_random_stress_seq");
    super.new(name);
  endfunction

  virtual task body();
    fifo_seq_item #(WIDTH) req;
    `uvm_info(get_type_name(), "Executing Randomized Stress Sequence (50 items)", UVM_LOW)
    repeat (50) begin
      req = fifo_seq_item #(WIDTH)::type_id::create("req");
      start_item(req);
      assert(req.randomize());
      finish_item(req);
    end
  endtask
endclass : fifo_random_stress_seq


//------------------------------------------------------------------------------
// 4. SEQUENCER (fifo_sequencer)
//------------------------------------------------------------------------------
// Arbitrates and channels sequence items to the driver.
//------------------------------------------------------------------------------
typedef uvm_sequencer #(fifo_seq_item #(16)) fifo_sequencer;


//------------------------------------------------------------------------------
// 5. DRIVER (fifo_driver)
//------------------------------------------------------------------------------
// Pulls transaction items from Sequencer and drives physical pins via interface.
//------------------------------------------------------------------------------
class fifo_driver #(parameter WIDTH = 16) extends uvm_driver #(fifo_seq_item #(WIDTH));
  `uvm_component_utils(fifo_driver #(WIDTH))

  virtual fifo_if #(WIDTH) vif;

  function new(string name = "fifo_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if #(WIDTH))::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Initialize signals
    vif.drv_cb.w_enb <= 0;
    vif.drv_cb.r_enb <= 0;
    vif.drv_cb.din   <= 0;

    // Wait for reset to de-assert before driving stimulus
    @(negedge vif.reset);
    @(vif.drv_cb);

    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  virtual task drive_item(fifo_seq_item #(WIDTH) item);
    @(vif.drv_cb);
    vif.drv_cb.w_enb <= item.w_enb;
    vif.drv_cb.r_enb <= item.r_enb;
    vif.drv_cb.din   <= item.din;
  endtask
endclass : fifo_driver


//------------------------------------------------------------------------------
// 6. MONITOR (fifo_monitor)
//------------------------------------------------------------------------------
// Passively observes pin activity, packages pin states into sequence items,
// and publishes them via an analysis port to Scoreboard & Coverage.
//------------------------------------------------------------------------------
class fifo_monitor #(parameter WIDTH = 16) extends uvm_monitor;
  `uvm_component_utils(fifo_monitor #(WIDTH))

  virtual fifo_if #(WIDTH) vif;
  uvm_analysis_port #(fifo_seq_item #(WIDTH)) item_collected_port;

  function new(string name = "fifo_monitor", uvm_component parent = null);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual fifo_if #(WIDTH))::get(this, "", "vif", vif))
      `uvm_fatal("NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
  endfunction

  virtual task run_phase(uvm_phase phase);
    fifo_seq_item #(WIDTH) item;

    // Wait for reset release
    @(negedge vif.reset);

    forever begin
      @(vif.mon_cb);
      // Create and populate transaction item after clock edge
      item = fifo_seq_item #(WIDTH)::type_id::create("mon_item");
      item.w_enb = vif.mon_cb.w_enb;
      item.r_enb = vif.mon_cb.r_enb;
      item.din   = vif.mon_cb.din;
      item.dout  = vif.mon_cb.dout;
      item.full  = vif.mon_cb.full;
      item.empty = vif.mon_cb.empty;

      `uvm_info(get_type_name(), $sformatf("Sampled: %s", item.convert2string()), UVM_HIGH)
      item_collected_port.write(item);
    end
  endtask
endclass : fifo_monitor


//------------------------------------------------------------------------------
// 7. FUNCTIONAL COVERAGE SUBSCRIBER (fifo_coverage)
//------------------------------------------------------------------------------
// Measures verification completeness: operations, flags, cross-coverage.
//------------------------------------------------------------------------------
class fifo_coverage #(parameter WIDTH = 16) extends uvm_subscriber #(fifo_seq_item #(WIDTH));
  `uvm_component_utils(fifo_coverage #(WIDTH))

  fifo_seq_item #(WIDTH) cov_item;

  covergroup fifo_cg;
    option.per_instance = 1;
    option.comment      = "Synchronous FIFO Functional Coverage";

    // Write Enable Coverage
    cp_w_enb : coverpoint cov_item.w_enb {
      bins write_idle = {0};
      bins write_act  = {1};
    }

    // Read Enable Coverage
    cp_r_enb : coverpoint cov_item.r_enb {
      bins read_idle = {0};
      bins read_act  = {1};
    }

    // Full Flag Coverage
    cp_full : coverpoint cov_item.full {
      bins not_full = {0};
      bins is_full  = {1};
    }

    // Empty Flag Coverage
    cp_empty : coverpoint cov_item.empty {
      bins not_empty = {0};
      bins is_empty  = {1};
    }

    // Cross Coverage: Operations vs FIFO State
    cross_rw_flags : cross cp_w_enb, cp_r_enb, cp_full, cp_empty {
      // Illegal state: FIFO cannot be full and empty simultaneously
      illegal_bins b_full_and_empty = binsof(cp_full.is_full) && binsof(cp_empty.is_empty);
    }
  endgroup

  function new(string name = "fifo_coverage", uvm_component parent = null);
    super.new(name, parent);
    fifo_cg = new();
  endfunction

  virtual function void write(fifo_seq_item #(WIDTH) t);
    cov_item = t;
    fifo_cg.sample();
  endfunction
endclass : fifo_coverage


//------------------------------------------------------------------------------
// 8. SCOREBOARD (fifo_scoreboard)
//------------------------------------------------------------------------------
// Compares DUT behavior against an ideal Software Reference Model (Queue).
// Validates: Data ordering (FIFO), Full/Empty flags, Overflow, Underflow.
//------------------------------------------------------------------------------
class fifo_scoreboard #(parameter WIDTH = 16, parameter DEPTH = 8) extends uvm_scoreboard;
  `uvm_component_utils(fifo_scoreboard #(WIDTH, DEPTH))

  uvm_analysis_imp #(fifo_seq_item #(WIDTH), fifo_scoreboard #(WIDTH, DEPTH)) item_imp;

  // Reference Model: Software Queue
  bit [WIDTH-1:0] ref_queue[$];

  // Pipeline tracking: RTL registers dout on posedge clk with a 1-cycle latency
  bit             expected_read_valid = 0;
  bit [WIDTH-1:0] expected_dout;

  // Verification metrics
  int match_count     = 0;
  int mismatch_count  = 0;
  int write_ops_count = 0;
  int read_ops_count  = 0;

  function new(string name = "fifo_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    item_imp = new("item_imp", this);
  endfunction

  virtual function void write(fifo_seq_item #(WIDTH) item);
    bit is_full  = (ref_queue.size() == DEPTH);
    bit is_empty = (ref_queue.size() == 0);

    // 1. Verify 1-cycle delayed read data integrity
    if (expected_read_valid) begin
      if (item.dout === expected_dout) begin
        `uvm_info("SCB_PASS", $sformatf("Data MATCH! dout=0x%04h (Expected: 0x%04h)",
                  item.dout, expected_dout), UVM_LOW)
        match_count++;
      end else begin
        `uvm_error("SCB_FAIL", $sformatf("Data MISMATCH! dout=0x%04h (Expected: 0x%04h)",
                   item.dout, expected_dout))
        mismatch_count++;
      end
      expected_read_valid = 0;
    end

    // 2. Verify Status Flags
    if (item.full !== is_full) begin
      `uvm_error("SCB_FLAG_ERR", $sformatf("FULL flag mismatch! DUT=%0b Expected=%0b (queue size=%0d)",
                 item.full, is_full, ref_queue.size()))
      mismatch_count++;
    end
    if (item.empty !== is_empty) begin
      `uvm_error("SCB_FLAG_ERR", $sformatf("EMPTY flag mismatch! DUT=%0b Expected=%0b (queue size=%0d)",
                 item.empty, is_empty, ref_queue.size()))
      mismatch_count++;
    end

    // 3. Process Read Operation in Reference Model
    if (item.r_enb && !is_empty) begin
      expected_dout       = ref_queue.pop_front();
      expected_read_valid = 1; // dout will be validated on the subsequent clock cycle
      read_ops_count++;
    end else if (item.r_enb && is_empty) begin
      `uvm_info("SCB_UNDERFLOW", "DUT correctly ignored Read attempt while EMPTY (Underflow guard checked)", UVM_MEDIUM)
    end

    // 4. Process Write Operation in Reference Model
    if (item.w_enb && !is_full) begin
      ref_queue.push_back(item.din);
      write_ops_count++;
    end else if (item.w_enb && is_full) begin
      `uvm_info("SCB_OVERFLOW", "DUT correctly ignored Write attempt while FULL (Overflow guard checked)", UVM_MEDIUM)
    end
  endfunction

  // Summary Report Phase
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCOREBOARD_SUMMARY", "--------------------------------------------------", UVM_NONE)
    `uvm_info("SCOREBOARD_SUMMARY", $sformatf("  Total Valid Writes Processed : %0d", write_ops_count), UVM_NONE)
    `uvm_info("SCOREBOARD_SUMMARY", $sformatf("  Total Valid Reads Checked    : %0d", read_ops_count), UVM_NONE)
    `uvm_info("SCOREBOARD_SUMMARY", $sformatf("  Data Matches                 : %0d", match_count), UVM_NONE)
    `uvm_info("SCOREBOARD_SUMMARY", $sformatf("  Data Mismatches              : %0d", mismatch_count), UVM_NONE)
    `uvm_info("SCOREBOARD_SUMMARY", $sformatf("  Residual Elements in FIFO    : %0d", ref_queue.size()), UVM_NONE)
    `uvm_info("SCOREBOARD_SUMMARY", "--------------------------------------------------", UVM_NONE)

    if (mismatch_count == 0 && match_count > 0)
      `uvm_info("TEST_RESULT", "*** TEST PASSED SUCCESSFULLY ***", UVM_NONE)
    else
      `uvm_error("TEST_RESULT", "*** TEST FAILED WITH MISMATCHES ***")
  endfunction
endclass : fifo_scoreboard


//------------------------------------------------------------------------------
// 9. AGENT (fifo_agent)
//------------------------------------------------------------------------------
// Encapsulates Sequencer, Driver, and Monitor into a reusable verification block.
// Can be configured as ACTIVE (Driver+Sequencer+Monitor) or PASSIVE (Monitor only).
//------------------------------------------------------------------------------
class fifo_agent #(parameter WIDTH = 16) extends uvm_agent;
  `uvm_component_utils(fifo_agent #(WIDTH))

  fifo_sequencer           seqr;
  fifo_driver  #(WIDTH)    drv;
  fifo_monitor #(WIDTH)    mon;

  function new(string name = "fifo_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = fifo_monitor #(WIDTH)::type_id::create("mon", this);

    if (get_is_active() == UVM_ACTIVE) begin
      seqr = fifo_sequencer::type_id::create("seqr", this);
      drv  = fifo_driver #(WIDTH)::type_id::create("drv", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Connect Driver to Sequencer via TLM seq_item_port
    if (get_is_active() == UVM_ACTIVE) begin
      drv.seq_item_port.connect(seqr.seq_item_export);
    end
  endfunction
endclass : fifo_agent


//------------------------------------------------------------------------------
// 10. ENVIRONMENT (fifo_env)
//------------------------------------------------------------------------------
// Top-level verification environment holding Agents, Scoreboard, and Coverage.
//------------------------------------------------------------------------------
class fifo_env #(parameter WIDTH = 16, parameter DEPTH = 8) extends uvm_env;
  `uvm_component_utils(fifo_env #(WIDTH, DEPTH))

  fifo_agent      #(WIDTH)         agent;
  fifo_scoreboard #(WIDTH, DEPTH) scb;
  fifo_coverage   #(WIDTH)         cov;

  function new(string name = "fifo_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = fifo_agent      #(WIDTH)::type_id::create("agent", this);
    scb   = fifo_scoreboard #(WIDTH, DEPTH)::type_id::create("scb", this);
    cov   = fifo_coverage   #(WIDTH)::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Connect Monitor TLM analysis port to Scoreboard & Coverage Subscribers
    agent.mon.item_collected_port.connect(scb.item_imp);
    agent.mon.item_collected_port.connect(cov.analysis_export);
  endfunction
endclass : fifo_env


//------------------------------------------------------------------------------
// 11. TESTS (fifo_test)
//------------------------------------------------------------------------------
// Configures the testbench, sets parameters, raises/drops objections, and runs
// sequence scenarios.
//------------------------------------------------------------------------------
class fifo_test extends uvm_test;
  `uvm_component_utils(fifo_test)

  localparam WIDTH = 16;
  localparam DEPTH = 8;

  fifo_env #(WIDTH, DEPTH) env;

  function new(string name = "fifo_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = fifo_env #(WIDTH, DEPTH)::type_id::create("env", this);
  endfunction

  // Hierarchical topology printing to inspect component tree
  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    fifo_write_seq         #(WIDTH, DEPTH) wr_seq;
    fifo_read_seq          #(WIDTH, DEPTH) rd_seq;
    fifo_simultaneous_seq  #(WIDTH)        sim_seq;
    fifo_random_stress_seq #(WIDTH)        rand_seq;

    phase.raise_objection(this, "Starting FIFO Full Verification Test");

    // Scenario 1: Fill FIFO completely + 2 overflow attempts
    `uvm_info("TEST", ">>> SCENARIO 1: WRITE & OVERFLOW <<<", UVM_LOW)
    wr_seq = fifo_write_seq #(WIDTH, DEPTH)::type_id::create("wr_seq");
    wr_seq.start(env.agent.seqr);

    #50;

    // Scenario 2: Drain FIFO completely + 2 underflow attempts
    `uvm_info("TEST", ">>> SCENARIO 2: READ & UNDERFLOW <<<", UVM_LOW)
    rd_seq = fifo_read_seq #(WIDTH, DEPTH)::type_id::create("rd_seq");
    rd_seq.start(env.agent.seqr);

    #50;

    // Scenario 3: Simultaneous Read and Write
    `uvm_info("TEST", ">>> SCENARIO 3: SIMULTANEOUS READ/WRITE <<<", UVM_LOW)
    sim_seq = fifo_simultaneous_seq #(WIDTH)::type_id::create("sim_seq");
    sim_seq.start(env.agent.seqr);

    #50;

    // Scenario 4: Randomized Stress Testing
    `uvm_info("TEST", ">>> SCENARIO 4: RANDOMIZED STRESS TEST <<<", UVM_LOW)
    rand_seq = fifo_random_stress_seq #(WIDTH)::type_id::create("rand_seq");
    rand_seq.start(env.agent.seqr);

    #100; // Allow remaining in-flight reads to settle in Scoreboard

    phase.drop_objection(this, "Finished FIFO Full Verification Test");
  endtask
endclass : fifo_test


//------------------------------------------------------------------------------
// 12. TOP MODULE (tb_top)
//------------------------------------------------------------------------------
// Testbench Top: Instantiates Clock generator, Reset logic, DUT, Interface,
// registers virtual interface with uvm_config_db, and triggers run_test().
//------------------------------------------------------------------------------
module tb_top;

  localparam DEPTH = 8;
  localparam WIDTH = 16;

  // 1. Clock Generation (100 MHz clock -> 10ns period)
  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  // 2. Interface Instance
  fifo_if #(WIDTH) intf (clk);

  // 3. DUT Instantiation
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
    .empty (intf.empty),
    .full  (intf.full)
  );

  // 4. Reset Generation
  initial begin
    intf.reset = 1'b1;
    #25;
    intf.reset = 1'b0;
  end

  // 5. Virtual Interface Configuration & Test Kickoff
  initial begin
    // Pass the virtual interface handle to UVM config DB
    uvm_config_db#(virtual fifo_if #(WIDTH))::set(null, "*", "vif", intf);

    // Dump waveform files for debugging (VCD / FSDB)
    $dumpfile("sync_fifo_uvm.vcd");
    $dumpvars(0, tb_top);

    // Launch the specified UVM test (can also be overridden via +UVM_TESTNAME=...)
    run_test("fifo_test");
  end

endmodule : tb_top
