# Micro-SIMD Vector Processing Unit (VPU)

## Overview

This is an area-optimized Micro-SIMD Vector Processing Unit designed for the Tiny Tapeout platform. The design targets the 1000 standard cell limit while providing full vector operation capabilities.

## Architecture

- **Data Width**: 8-bit
- **Register File**: 4×8-bit (R0, R1, R2, R3)
- **Tile Size**: 1x1
- **Clock**: External

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

## Pinout

### Inputs (ui_in[7:0])
- ui_in[3:0]: Opcode
- ui_in[5:4]: Source Register A
- ui_in[7:6]: Source Register B

### Outputs (uo_out[7:0])
- uo_out[7:0]: ALU Result

### Bidirectional (uio_inout[7:0])
- In NOP mode: Outputs selected register value
- In operation mode: Can be used for immediate values

## Resource Estimation

| Component | Approx. Cells | Notes |
|-----------|---------------|-------|
| Register File (4×8-bit) | ~32 DFFs | 32 flip-flops for storage |
| 8-bit ALU | ~80-120 cells | Shared adder/subtractor, bitwise ops |
| Control FSM (binary encoded) | ~20-30 cells | 3-bit state, 4-bit opcode decoder |
| Input/Output Muxes | ~100-150 cells | Register select and routing |
| **Total** | **~250-350 cells** | Well under 1000-cell limit |

## Area Optimization Techniques

1. **Binary FSM Encoding**: Uses 3 bits for state instead of 8 one-hot states, saving 5 flip-flops
2. **Shared Adder/Subtractor**: Same hardware performs both operations by inverting B input
3. **Direct Register Indexing**: No complex address decoder - simple 2-bit select directly indexes 4 registers
4. **Minimal Control Logic**: Opcode decode is purely combinational, no extra flip-flops
5. **Accumulator-Style Operations**: Destination defaults to source A register, reducing routing complexity
6. **No Multipliers**: All multiplication-like operations use shift-and-add logic

## Testing

Run the testbench with your preferred Verilog simulator:

```bash
iverilog -o tb tt_um_vpu.v tb.sv
vvp tb
```

## Usage Example

```verilog
// Load R0 with 0x05 (using ADD with zero)
ui_in = {2'b00, 2'b00, OP_ADD};  // R0 = R0 + R0 (assuming R0=0)

// Add R1 to R0
ui_in = {2'b00, 2'b01, OP_ADD};  // R0 = R0 + R1

// Read R0 via bidirectional bus
ui_in = {2'b00, 2'b00, OP_NOP};  // Read R0
```

## License

Apache-2.0
