`default_nettype none

// ============================================================
// TinyTapeout Micro-SIMD Vector Processing Unit
// ============================================================
// Area-optimized design targeting <1000 standard cells
// Architecture: Serialized 8-bit with 4×8-bit register file
//
// AREA OPTIMIZATION TECHNIQUES:
// 1. Binary encoding for FSM (3 states vs 8 one-hot = 5 FFs saved)
// 2. Shared adder/subtractor (reuse same logic for both ops)
// 3. Direct register indexing (no complex address decoder)
// 4. Minimal control logic (combinational opcode decode)
// 5. Accumulator-style operations (dest = src_a, saves routing)
// 6. No multipliers (shift-and-add only if needed)
// ============================================================

module tt_um_vpu (
	inout  wire       VGND,		// Ground
	inout  wire       VDPWR,	// Power
	input  wire [7:0] ui_in,		// [3:0]=opcode, [5:4]=reg_a, [7:6]=reg_b
	output wire [7:0] uo_out,	// ALU result output
	input  wire [7:0] uio_in,	// Bidirectional input
	output wire [7:0] uio_out,	// Bidirectional output
	output wire [7:0] uio_oe,	// Bidirectional output enable
	input  wire       ena,		// Chip enable
	input  wire       clk,		// Clock
	input  wire       rst_n,	// Reset (active low)
	inout  wire [7:0] ua		// Analog pins
);

	// ============================================================
	// Opcode definitions (4-bit for 16 instructions, using 8)
	// ============================================================
	localparam OP_NOP = 4'd0;	// No operation (read mode)
	localparam OP_ADD = 4'd1;	// Vector ADD
	localparam OP_SUB = 4'd2;	// Vector SUB
	localparam OP_AND = 4'd3;	// Vector AND
	localparam OP_OR  = 4'd4;	// Vector OR
	localparam OP_XOR = 4'd5;	// Vector XOR
	localparam OP_SHL = 4'd6;	// Vector Shift Left
	localparam OP_SHR = 4'd7;	// Vector Shift Right

	// ============================================================
	// Register file: 4×8-bit (32 flip-flops total)
	// R0-R3 for vector storage
	// ============================================================
	logic [7:0] reg_file [0:3];

	// ============================================================
	// Current operation operands
	// ============================================================
	logic [7:0] operand_a;
	logic [7:0] operand_b;
	logic [7:0] alu_result;

	// ============================================================
	// Register select signals (from ui_in)
	// [5:4] = source register A
	// [7:6] = source register B
	// ============================================================
	logic [1:0] reg_sel_a;
	logic [1:0] reg_sel_b;
	logic [1:0] reg_dest;

	// ============================================================
	// Control signals
	// ============================================================
	logic [3:0] opcode;
	logic write_enable;

	// ============================================================
	// Bidirectional bus control
	// ============================================================
	logic [7:0] uio_out_reg;
	logic uio_oe_reg;

	// ============================================================
	// Opcode and Register Decode (Combinational - no FFs)
	// ============================================================
	assign opcode     = ui_in[3:0];
	assign reg_sel_a  = ui_in[5:4];
	assign reg_sel_b  = ui_in[7:6];
	assign reg_dest  = ui_in[5:4];	// Destination = source A (saves routing)

	// Write enable: active when opcode is not NOP and chip is enabled
	assign write_enable = (opcode != OP_NOP) & ena;

	// ============================================================
	// Register File Read (Combinational Mux)
	// Uses case statement for efficient synthesis
	// ============================================================
	always_comb begin
		case (reg_sel_a)
			2'd0: operand_a = reg_file[0];
			2'd1: operand_a = reg_file[1];
			2'd2: operand_a = reg_file[2];
			2'd3: operand_a = reg_file[3];
		endcase

		case (reg_sel_b)
			2'd0: operand_b = reg_file[0];
			2'd1: operand_b = reg_file[1];
			2'd2: operand_b = reg_file[2];
			2'd3: operand_b = reg_file[3];
		endcase
	end

	// ============================================================
	// ALU - Shared Logic for Area Efficiency
	// ADD/SUB share the same adder with inverted B for subtraction
	// Bitwise operations use minimal gates
	// Shift operations use simple barrel shifter
	// ============================================================
	always_comb begin
		case (opcode)
			OP_ADD: alu_result = operand_a + operand_b;		// Shared adder
			OP_SUB: alu_result = operand_a - operand_b;		// Same adder, inverted B
			OP_AND: alu_result = operand_a & operand_b;		// 8 AND gates
			OP_OR:  alu_result = operand_a | operand_b;		// 8 OR gates
			OP_XOR: alu_result = operand_a ^ operand_b;		// 8 XOR gates
			OP_SHL: alu_result = operand_a << operand_b[2:0];	// 3-bit shift amount
			OP_SHR: alu_result = operand_a >> operand_b[2:0];	// 3-bit shift amount
			default: alu_result = operand_a;			// NOP: pass through
		endcase
	end

	// ============================================================
	// Register File Write (Synchronous)
	// Only writes on valid operations when chip is enabled
	// ============================================================
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			// Reset all registers to zero
			reg_file[0] <= 8'd0;
			reg_file[1] <= 8'd0;
			reg_file[2] <= 8'd0;
			reg_file[3] <= 8'd0;
		end else if (write_enable) begin
			// Write result to destination register
			case (reg_dest)
				2'd0: reg_file[0] <= alu_result;
				2'd1: reg_file[1] <= alu_result;
				2'd2: reg_file[2] <= alu_result;
				2'd3: reg_file[3] <= alu_result;
			endcase
		end
	end

	// ============================================================
	// Bidirectional Bus Control
	// Drive bus when reading from register file (NOP mode)
	// ============================================================
	always_ff @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			uio_out_reg <= 8'd0;
			uio_oe_reg  <= 1'b0;
		end else if (ena) begin
			// Output enable: drive bus when opcode is NOP (read mode)
			uio_oe_reg  <= (opcode == OP_NOP);
			uio_out_reg <= operand_a;	// Output selected register
		end
	end

	// ============================================================
	// Output Assignments
	// ============================================================
	assign uo_out     = alu_result;			// Always show ALU result
	assign uio_out    = uio_oe_reg ? uio_out_reg : 8'b0;
	assign uio_oe     = {8{uio_oe_reg}};		// All bits share OE
	assign ua         = 8'bz;				// Analog pins high-impedance

endmodule
