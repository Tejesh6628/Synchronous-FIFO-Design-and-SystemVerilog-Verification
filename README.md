# Synchronous FIFO — Design & SystemVerilog Layered OOP Verification

A parameterizable **Synchronous FIFO** (First-In, First-Out) buffer implemented in Verilog, verified using a modular, class-based **SystemVerilog OOP Layered Testbench** with constrained-random stimulus and an automated self-checking scoreboard.

---

## 📐 FIFO Architecture

```
            ┌─────────────────────────────────┐
   din ────►│                                 │────► dout
  w_enb ───►│       FIFO Memory Array         │
  r_enb ───►│     (Depth × Width bits)        │
            │                                 │
   clk ────►│   wptr ──►  [ ][ ][ ]...        │────► full
 reset ────►│   rptr ──►  count tracker       │────► empty
            └─────────────────────────────────┘
```

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `reset` | Input | 1 | Asynchronous active-high reset |
| `w_enb` | Input | 1 | Write enable |
| `r_enb` | Input | 1 | Read enable |
| `din` | Input | `Width` | Data input |
| `dout` | Output | `Width` | Data output |
| `full` | Output | 1 | High when FIFO is full |
| `empty` | Output | 1 | High when FIFO is empty |

### Design Highlights
- **Parameterizable** depth (default 8) and data width (default 16-bit).
- **Circular buffer** using modular pointer indexing (`wptr`, `rptr`).
- **Internal counter** (`count`) for clean flag generation.
- **Overflow & underflow protection** against illegal read/write operations.
- **Simultaneous Read & Write** supported without losing data integrity.

---

## 📁 Repository Structure

```
.
├── sync_fifo.v                    # RTL design of synchronous FIFO
├── sync_fifo_tb.v                 # Directed Verilog testbench
├── sync_fifo_sv_tb.sv             # SystemVerilog OOP Layered testbench
├── sync_fifo_monitor_verilog.txt  # Directed simulation transcript ($monitor output)
├── waveform.png                   # Simulation waveform screenshot (Vivado)
└── README.md                      # Project documentation
```

---

## 🏗️ SystemVerilog Layered OOP Architecture

The verification environment (`sync_fifo_sv_tb.sv`) follows the industry-standard modular layered architecture using SystemVerilog classes, mailboxes, and virtual interfaces:

```
┌────────────────────────────────────────────────────────┐
│                      environment                       │
│                                                        │
│  ┌───────────┐  gen2drv   ┌────────┐   vif   ┌──────┐  │
│  │ generator │──mailbox──►│ driver │────────►│ DUT  │  │
│  └───────────┘            └────────┘         └──┬───┘  │
│                                                 │      │
│  ┌────────────┐ mon2scb   ┌─────────┐   vif     │      │
│  │ scoreboard │◄─mailbox──│ monitor │◄──────────┘      │
│  └────────────┘           └─────────┘                  │
└────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Class Type | Role & Responsibilities |
|---|---|---|
| **Transaction** | `class transaction` | Holds randomized stimulus data (`w_enb`, `r_enb`, `din`) and outputs (`dout`, `full`, `empty`). Includes constraints to prevent illegal idle cycles. |
| **Generator** | `class generator` | Creates transaction objects, applies constrained-random stimulus for 5 test phases (fill, overflow, drain, underflow, random R/W), and delivers them via `gen2drv` mailbox. |
| **Driver** | `class driver` | Retrieves transactions from `gen2drv` mailbox and drives the physical interface pins on `negedge clk` to maintain stable 5ns setup time. |
| **Monitor** | `class monitor` | Passively samples the interface pins on `posedge clk + 1ns` and forwards active write/read transactions into `mon2scb` mailbox. |
| **Scoreboard** | `class scoreboard` | Implements a golden reference model using an unbounded queue (`ref_fifo[$]`). Automatically compares DUT output against expected data and validates `full`/`empty` flag correctness. |
| **Environment** | `class environment` | Instantiates transactors, connects mailboxes (`gen2drv`, `mon2scb`), and launches concurrent execution using `fork ... join_any`. |
| **Interface** | `interface fifo_if` | Encapsulates all FIFO signals and provides clean connectivity between testbench classes and RTL DUT. |

---

## 🧪 Verification Plan & Test Scenarios

The generator systematically verifies the FIFO through 5 distinct test phases:

1. **Write Burst**: Fills the FIFO to its full capacity (8 writes); validates `full` flag assertion.
2. **Overflow Test**: Attempts to write into a full FIFO; verifies data is not overwritten and count does not increment.
3. **Read Burst**: Drains all items from the FIFO; validates FIFO ordering and `empty` flag assertion.
4. **Underflow Test**: Attempts to read from an empty FIFO; verifies no invalid data is produced.
5. **Random Concurrent R/W**: Stresses simultaneous read and write operations; verifies pointers and data integrity under continuous load.

---

## 🚀 How to Run in Xilinx Vivado

1. Open Vivado and add `sync_fifo.v` as a **Design Source**.
2. Add `sync_fifo_sv_tb.sv` as a **Simulation Source** (file type: **SystemVerilog**).
3. In the Sources window under `sim_1`, right-click `tb_top` $\rightarrow$ **Set as Top**.
4. In Flow Navigator, click **Run Simulation $\rightarrow$ Run Behavioral Simulation**.
5. Check the Vivado **Tcl Console** for the automated scoreboard report:
   ```text
   Test 1: Writing 8 items to fill FIFO
   Test 2: Overflow test (writing to full FIFO)
   Test 3: Reading 8 items to empty FIFO
   [SCB] MATCH: dout = 0x35a2 (exp = 0x35a2)
   ...
   Test 4: Underflow test (reading from empty FIFO)
   Test 5: Random concurrent read and write operations
   [SCB] MATCH: ...

   --- SCOREBOARD SUMMARY ---
   Matches: 19 | Errors: 0
   Status: PASSED
   ```
