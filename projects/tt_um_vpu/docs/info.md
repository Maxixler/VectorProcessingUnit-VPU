# Micro-SIMD Vector Processing Unit Overview

This project implements an **area-optimized Micro-SIMD Vector Processing Unit (VPU)** in the Sky130 process. The design targets the 1000 standard cell limit while providing full vector operation capabilities.

## Architecture

The design consists of:

* 4×8-bit register file (R0, R1, R2, R3)
* 8-bit ALU with shared adder/subtractor
* Binary-encoded control FSM
* Minimal control logic for area efficiency

## Key Features

* Technology: Sky130 (1.8V)
* Data Width: 8-bit
* Register File: 4×8-bit
* Tile Size: 1x1
* Area: ~250-350 standard cells

## Instruction Set

| Opcode | Operation | Description |
|--------|-----------|-------------|
| 0x0 | NOP | No operation (read mode) |
| 0x1 | ADD | Vector ADD: R[dest] = R[a] + R[b] |
| 0x2 | SUB | Vector SUB: R[dest] = R[a] - R[b] |
| 0x3 | AND | Vector AND: R[dest] = R[a] & R[b] |
| 0x4 | OR | Vector OR: R[dest] = R[a] \| R[b] |
| 0x5 | XOR | Vector XOR: R[dest] = R[a] ^ R[b] |
| 0x6 | SHL | Vector Shift Left: R[dest] = R[a] << R[b][2:0] |
| 0x7 | SHR | Vector Shift Right: R[dest] = R[a] >> R[b][2:0] |

## Tiny Tapeout Integration

* Opcode: ui_in[3:0]
* Source Register A: ui_in[5:4]
* Source Register B: ui_in[7:6]
* Result: uo_out[7:0]
* Bidirectional Data: uio_inout[7:0]

## Area Optimization Techniques

1. Binary FSM Encoding (3 bits vs 8 one-hot)
2. Shared Adder/Subtractor
3. Direct Register Indexing
4. Minimal Control Logic
5. Accumulator-Style Operations
6. No Multipliers (shift-and-add only)

## Notes

* All operations are single-cycle
* Register file resets to zero on rst_n
* Bidirectional bus outputs register value in NOP mode
