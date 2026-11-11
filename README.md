# Synchronous FIFO — Design & Verification (Verilog)

A parameterizable **Synchronous FIFO** (First-In, First-Out) buffer implemented in Verilog with a comprehensive testbench. The design uses a single clock domain for both read and write operations and includes full/empty status flags.

---

## 📐 Architecture

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
- **Circular buffer** using modular wrap-around pointers (`wptr`, `rptr`).
- **Element counter** (`count`) for clean full/empty flag generation.
- **Overflow protection** — writes are ignored when `full` is asserted.
- **Underflow protection** — reads are ignored when `empty` is asserted.
- **Simultaneous R/W** support — count remains stable during concurrent read and write.

---

## 📁 Repository Structure

```
Synchronous_FIFO/
├── sync_fifo.v              # RTL design of the synchronous FIFO
├── sync_fifo_tb.v           # Verilog testbench
├── sync_fifo_monitor.txt    # Simulation log ($monitor output)
├── waveform.png             # Simulation waveform screenshot (Vivado)
└── README.md                # This file
```

---

## 🧪 Testbench & Verification

The testbench (`sync_fifo_tb.v`) exercises the FIFO through five scenarios:

| # | Test | What It Verifies |
|---|------|------------------|
| 1 | **Write Test** | Fills the FIFO with 8 random 16-bit values; `full` flag asserts after the 8th write. |
| 2 | **Overflow Test** | Attempts 2 more writes while `full = 1`; data and count must not change. |
| 3 | **Read Test** | Drains all 8 entries in FIFO order; `empty` flag asserts after the last read. |
| 4 | **Underflow Test** | Attempts reads while `empty = 1`; output and count must remain stable. |
| 5 | **Simultaneous R/W** | Asserts both `w_enb` and `r_enb` together; count stays constant, data flows through. |
| 6 | **Alternating R/W** | Alternates single writes and reads to verify pointer tracking. |

### Simulation Waveform

![Simulation Waveform](waveform.png)

> Captured from **Xilinx Vivado** Behavioral Simulation showing `clk`, `reset`, `w_enb`, `r_enb`, `din`, `dout`, `full`, and `empty` signals.

---

## 🚀 How to Run

### Using Xilinx Vivado

1. Create a new project and add `sync_fifo.v` as a design source.
2. Add `sync_fifo_tb.v` as a simulation source.
3. Run **Behavioral Simulation**.

### Using Icarus Verilog (open-source)

```bash
iverilog -o sync_fifo_tb.vvp sync_fifo.v sync_fifo_tb.v
vvp sync_fifo_tb.vvp
```

---

## ⚙️ Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `Depth` | 8 | Number of entries in the FIFO |
| `Width` | 16 | Bit-width of each data entry |

Override at instantiation:

```verilog
sync_fifo #(.Depth(16), .Width(32)) my_fifo ( ... );
```

---

## 📄 License

This project is open-source and available for educational and personal use.
