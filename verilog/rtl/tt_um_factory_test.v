//============================================================================
// tt_um_vpu.sv
//
// Micro-SIMD General Purpose Vector Processing Unit
// Target  : Tiny Tapeout 1x1 tile (~1000 standard cells max)
// PDK     : sg13g2 (IHP 130nm) or sky130_fd_sc_hd (Skywater) — process agnostic
//
// ARCHITECTURE
// ------------
//   2-lane x 4-bit parallel SIMD datapath.
//   Accumulator-based register file: one ACC + one B operand register.
//   Carries do NOT propagate between lanes — each 4-bit lane is independent.
//   This is the defining property of SIMD addition demonstrated by this VPU.
//
// ISA  (3-bit opcode, 8 instructions total)
// -----------------------------------------
//   000 ADD   : ACC <- ACC + B    (per-lane, no inter-lane carry)
//   001 SUB   : ACC <- ACC - B    (per-lane, no inter-lane borrow)
//   010 AND   : ACC <- ACC & B
//   011 OR    : ACC <- ACC | B
//   100 XOR   : ACC <- ACC ^ B
//   101 SHL   : ACC <- ACC << 1   (per-lane logical left shift by 1)
//   110 SHR   : ACC <- ACC >> 1   (per-lane logical right shift by 1)
//   111 PASS  : ACC <- B          (move B -> ACC, useful as broadcast)
//
// PIN MAP
// -------
//   ui_in [7:0]       : 8-bit vector data bus  ( lane1[3:0] | lane0[3:0] )
//   uo_out[7:0]       : ACC register, always visible
//   uio_in[2:0]       : opcode (3-bit)
//   uio_in[4:3]       : phase  (2-bit)
//                          00 IDLE       — registers hold
//                          01 LOAD_ACC   — ACC <- ui_in
//                          10 LOAD_B     — B   <- ui_in
//                          11 EXEC       — ACC <- ALU(opcode, ACC, B)
//   uio_in[7:5]       : reserved (tied off internally for lint cleanliness)
//   uio_out / uio_oe  : driven low (all uio bits are configured as inputs)
//
//
// AREA-OPTIMIZATION TECHNIQUES APPLIED
// ====================================
//
//  [O1] Accumulator architecture
//       Only TWO 8-bit vector regs (ACC, B) instead of a 3-operand register
//       file. Saves 8 FFs (>= ~8 cells) and the associated 3:1 read mux.
//
//  [O2] Add/Sub adder reuse
//       Subtraction is performed by the SAME adder by inverting B and
//       forcing carry-in to 1 (two's complement on the fly). This eliminates
//       a dedicated subtractor block — saves ~16 cells per lane (~32 total).
//
//  [O3] Shifts are pure routing
//       Fixed shift-by-1 in each lane is implemented as wire reordering
//       with a hard-wired 1'b0 fill bit. ZERO standard cells, ZERO FFs.
//       No barrel shifter, no shift-amount decoder.
//
//  [O4] Binary-encoded phase (per spec)
//       Phase is 2 bits, decoded combinationally inside the always block's
//       case statement. No one-hot phase FFs are stored — saves 2 FFs vs
//       a one-hot {idle, load_acc, load_b, exec} encoding.
//
//  [O5] Logical ops are bit-parallel
//       AND/OR/XOR are computed once on the full 8-bit vector, not 2x4-bit.
//       Lane-independence is automatic for bitwise ops.
//
//  [O6] No multipliers, no '*' operator
//       The ISA contains zero multiplication primitives. Any future product
//       would be implemented strictly as shift-and-add via SHL/ADD pairs
//       under software control, never as a hardware multiplier.
//
//  [O7] Combined LOAD/EXEC phase encoding
//       The phase field doubles as both a register-write selector and an
//       execute pulse — no separate "go" bit, no FSM state register beyond
//       the data registers themselves. The control plane is effectively
//       stateless.
//
//
// RESOURCE ESTIMATE  (approximate, gate-equivalent)
// =================================================
//   Flip-Flops:
//     ACC                                 8
//     B_REG                               8
//                                       ----
//     Total FFs:                         16
//
//   Combinational cells:
//     2x 4-bit add/sub (with B XOR)     ~32
//     8-bit AND/OR/XOR (3 ops)          ~24
//     Per-lane SHL/SHR                    0   (pure wiring)
//     8-way 8-bit result mux            ~64
//     ACC source 3:1 mux (load paths)   ~16
//     Phase / opcode decode              ~5
//                                       ----
//     Total combinational:              ~141
//
//   GRAND TOTAL: ~157 standard cells  (well within 1000-cell budget)
//
//
// RESOURCE-SHARING NOTE
// ---------------------
//   The spec mentions optionally time-multiplexing one 4-bit ALU across
//   both lanes. This was NOT done because the parallel SIMD path is well
//   under budget (~16% utilization) and parallelism is the entire point
//   of the design. The hooks for serialization (a lane_select FF + a 4-bit
//   ALU + a 2:1 operand mux) would be a straightforward future shrink if
//   ever required for a smaller tile.
//============================================================================

`default_nettype none

module tt_um_vpu (
    input  wire [7:0] ui_in,    // Dedicated inputs  — vector data bus
    output wire [7:0] uo_out,   // Dedicated outputs — ACC register view
    input  wire [7:0] uio_in,   // Bidir input path  — control bus
    output wire [7:0] uio_out,  // Bidir output path (unused, tied low)
    output wire [7:0] uio_oe,   // Bidir output enable (all 0 -> all inputs)
    input  wire       ena,      // Power enable from TT mux (always 1 active)
    input  wire       clk,
    input  wire       rst_n     // Active-low asynchronous reset
);

    //------------------------------------------------------------------------
    // Bidirectional pin configuration: every uio is an input
    //------------------------------------------------------------------------
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    //------------------------------------------------------------------------
    // Control field decode  [O4]
    //------------------------------------------------------------------------
    wire [2:0] opcode = uio_in[2:0];
    wire [1:0] phase  = uio_in[4:3];

    localparam [1:0] PH_IDLE     = 2'b00;
    localparam [1:0] PH_LOAD_ACC = 2'b01;
    localparam [1:0] PH_LOAD_B   = 2'b10;
    localparam [1:0] PH_EXEC     = 2'b11;

    localparam [2:0] OP_ADD  = 3'b000;
    localparam [2:0] OP_SUB  = 3'b001;
    localparam [2:0] OP_AND  = 3'b010;
    localparam [2:0] OP_OR   = 3'b011;
    localparam [2:0] OP_XOR  = 3'b100;
    localparam [2:0] OP_SHL  = 3'b101;
    localparam [2:0] OP_SHR  = 3'b110;
    localparam [2:0] OP_PASS = 3'b111;

    //------------------------------------------------------------------------
    // Vector register file [O1] — only TWO 8-bit registers => 16 FFs total
    //------------------------------------------------------------------------
    reg [7:0] acc;     // Accumulator (also the architectural output)
    reg [7:0] b_reg;   // Operand register

    // Per-lane wiring views — these synthesize to nothing, just naming.
    wire [3:0] acc_l0 = acc[3:0];
    wire [3:0] acc_l1 = acc[7:4];
    wire [3:0] b_l0   = b_reg[3:0];
    wire [3:0] b_l1   = b_reg[7:4];

    //------------------------------------------------------------------------
    // SIMD ALU
    //
    // Two independent 4-bit lanes execute in parallel. The carry-out of
    // lane0's adder is DISCARDED — it does not propagate into lane1's
    // adder. This is what makes this an honest SIMD ALU rather than just
    // an 8-bit ALU.
    //
    // [O2] Add and Sub share the same physical adders.
    //      For SUB: B' = ~B and carry-in = 1  (two's complement).
    //------------------------------------------------------------------------
    wire is_sub = (opcode == OP_SUB);

    wire [3:0] addsub_b_l0 = b_l0 ^ {4{is_sub}};
    wire [3:0] addsub_b_l1 = b_l1 ^ {4{is_sub}};

    // Independent 4-bit adders — carry-out is intentionally truncated
    // so it cannot leak between lanes.
    wire [3:0] sum_l0 = acc_l0 + addsub_b_l0 + {3'b000, is_sub};
    wire [3:0] sum_l1 = acc_l1 + addsub_b_l1 + {3'b000, is_sub};

    // [O5] Bitwise logic — single 8-bit operation, lane-agnostic.
    wire [7:0] and_r = acc & b_reg;
    wire [7:0] or_r  = acc | b_reg;
    wire [7:0] xor_r = acc ^ b_reg;

    // [O3] Per-lane fixed shift-by-1, implemented as routing only.
    //   SHL: each 4-bit lane shifted left  by 1, zero filled
    //   SHR: each 4-bit lane shifted right by 1, zero filled (logical)
    wire [7:0] shl_r = {acc[6:4], 1'b0, acc[2:0], 1'b0};
    wire [7:0] shr_r = {1'b0, acc[7:5], 1'b0, acc[3:1]};

    // 8-way result mux — the largest combinational block in the design.
    reg [7:0] alu_result;
    always @* begin
        case (opcode)
            OP_ADD  : alu_result = {sum_l1, sum_l0};
            OP_SUB  : alu_result = {sum_l1, sum_l0};
            OP_AND  : alu_result = and_r;
            OP_OR   : alu_result = or_r;
            OP_XOR  : alu_result = xor_r;
            OP_SHL  : alu_result = shl_r;
            OP_SHR  : alu_result = shr_r;
            OP_PASS : alu_result = b_reg;
            default : alu_result = 8'h00;
        endcase
    end

    //------------------------------------------------------------------------
    // Sequential update — phase-driven write enables [O7]
    //
    // The phase field IS the FSM. There is no separate state register.
    //------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc   <= 8'h00;
            b_reg <= 8'h00;
        end else begin
            case (phase)
                PH_LOAD_ACC : acc   <= ui_in;
                PH_LOAD_B   : b_reg <= ui_in;
                PH_EXEC     : acc   <= alu_result;
                default     : ;  // PH_IDLE — both registers hold value
            endcase
        end
    end

    //------------------------------------------------------------------------
    // Output drive
    //------------------------------------------------------------------------
    assign uo_out = acc;

    //------------------------------------------------------------------------
    // Lint suppression for legitimately unused signals.
    //   ena         — TT power enable, design is always live when ena=1
    //   uio_in[7:5] — reserved for future ISA extensions
    //------------------------------------------------------------------------
    wire _unused = &{ena, uio_in[7:5], 1'b0};

endmodule

`default_nettype wire
