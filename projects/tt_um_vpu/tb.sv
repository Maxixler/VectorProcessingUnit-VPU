`timescale 1ns/1ps

// ============================================================
// Testbench for tt_um_vpu
// ============================================================

module tb_vpu;

	// Testbench signals
	reg clk;
	reg rst_n;
	reg [7:0] ui_in;
	reg [7:0] uio_in;
	wire [7:0] uo_out;
	wire [7:0] uio_out;
	wire [7:0] uio_oe;
	reg ena;

	// Opcode definitions (must match module)
	localparam OP_NOP = 4'd0;
	localparam OP_ADD = 4'd1;
	localparam OP_SUB = 4'd2;
	localparam OP_AND = 4'd3;
	localparam OP_OR  = 4'd4;
	localparam OP_XOR = 4'd5;
	localparam OP_SHL = 4'd6;
	localparam OP_SHR = 4'd7;

	// Instantiate DUT
	tt_um_vpu dut (
		.ui_in(ui_in),
		.uo_out(uo_out),
		.uio_in(uio_in),
		.uio_out(uio_out),
		.uio_oe(uio_oe),
		.ena(ena),
		.clk(clk),
		.rst_n(rst_n)
	);

	// Clock generation
	initial begin
		clk = 0;
		forever #5 clk = ~clk;  // 100MHz clock
	end

	// Test stimulus
	initial begin
		// Initialize
		rst_n = 0;
		ui_in = 8'h00;
		uio_in = 8'h00;
		ena = 1'b0;
		#20;
		rst_n = 1;
		#10;
		ena = 1'b1;

		$display("========================================");
		$display("=== VPU Testbench Started ===");
		$display("========================================");
		$display("Time | Opcode | RegA | RegB | Result");
		$display("----------------------------------------");

		// ============================================================
		// Initialize registers by adding from uio_in
		// Since we don't have a LOAD instruction, we use ADD with zero
		// ============================================================

		// Load R0 = 0x05 (R0 = R0 + 0x05, assuming R0 starts at 0)
		uio_in = 8'h05;
		ui_in = {2'b00, 2'b00, OP_ADD};  // R0 = R0 + R0 (with uio_in as operand)
		#10;
		$display("%0t | LOAD   | R0   | -    | %h", $time, uo_out);

		// Load R1 = 0x03
		uio_in = 8'h03;
		ui_in = {2'b01, 2'b01, OP_ADD};  // R1 = R1 + R1
		#10;
		$display("%0t | LOAD   | R1   | -    | %h", $time, uo_out);

		// Load R2 = 0x0F
		uio_in = 8'h0F;
		ui_in = {2'b10, 2'b10, OP_ADD};  // R2 = R2 + R2
		#10;
		$display("%0t | LOAD   | R2   | -    | %h", $time, uo_out);

		// Load R3 = 0x55
		uio_in = 8'h55;
		ui_in = {2'b11, 2'b11, OP_ADD};  // R3 = R3 + R3
		#10;
		$display("%0t | LOAD   | R3   | -    | %h", $time, uo_out);

		// ============================================================
		// Test ADD: R0 = R0 + R1 (0x05 + 0x03 = 0x08)
		// ============================================================
		ui_in = {2'b00, 2'b01, OP_ADD};  // R0 = R0 + R1
		#10;
		$display("%0t | ADD    | R0   | R1   | %h", $time, uo_out);
		if (uo_out !== 8'h08) $display("ERROR: Expected 0x08, got %h", uo_out);

		// ============================================================
		// Test SUB: R0 = R0 - R1 (0x08 - 0x03 = 0x05)
		// ============================================================
		ui_in = {2'b00, 2'b01, OP_SUB};  // R0 = R0 - R1
		#10;
		$display("%0t | SUB    | R0   | R1   | %h", $time, uo_out);
		if (uo_out !== 8'h05) $display("ERROR: Expected 0x05, got %h", uo_out);

		// ============================================================
		// Test AND: R2 = R2 & R3 (0x0F & 0x55 = 0x05)
		// ============================================================
		ui_in = {2'b10, 2'b11, OP_AND};  // R2 = R2 & R3
		#10;
		$display("%0t | AND    | R2   | R3   | %h", $time, uo_out);
		if (uo_out !== 8'h05) $display("ERROR: Expected 0x05, got %h", uo_out);

		// ============================================================
		// Test OR: R2 = R2 | R3 (0x05 | 0x55 = 0x55)
		// ============================================================
		ui_in = {2'b10, 2'b11, OP_OR};  // R2 = R2 | R3
		#10;
		$display("%0t | OR     | R2   | R3   | %h", $time, uo_out);
		if (uo_out !== 8'h55) $display("ERROR: Expected 0x55, got %h", uo_out);

		// ============================================================
		// Test XOR: R2 = R2 ^ R3 (0x55 ^ 0x55 = 0x00)
		// ============================================================
		ui_in = {2'b10, 2'b11, OP_XOR};  // R2 = R2 ^ R3
		#10;
		$display("%0t | XOR    | R2   | R3   | %h", $time, uo_out);
		if (uo_out !== 8'h00) $display("ERROR: Expected 0x00, got %h", uo_out);

		// ============================================================
		// Reload R2 with 0x01 for shift tests
		// ============================================================
		uio_in = 8'h01;
		ui_in = {2'b10, 2'b10, OP_ADD};  // R2 = R2 + R2
		#10;
		$display("%0t | LOAD   | R2   | -    | %h", $time, uo_out);

		// ============================================================
		// Test SHL: R2 = R2 << 2 (0x01 << 2 = 0x04)
		// ============================================================
		uio_in = 8'h02;  // Shift amount
		ui_in = {2'b10, 2'b10, OP_SHL};  // R2 = R2 << R2 (using R2 as shift amount)
		#10;
		$display("%0t | SHL    | R2   | R2   | %h", $time, uo_out);
		if (uo_out !== 8'h04) $display("ERROR: Expected 0x04, got %h", uo_out);

		// ============================================================
		// Test SHR: R2 = R2 >> 1 (0x04 >> 1 = 0x02)
		// ============================================================
		uio_in = 8'h01;  // Shift amount
		ui_in = {2'b10, 2'b10, OP_SHR};  // R2 = R2 >> R2
		#10;
		$display("%0t | SHR    | R2   | R2   | %h", $time, uo_out);
		if (uo_out !== 8'h02) $display("ERROR: Expected 0x02, got %h", uo_out);

		// ============================================================
		// Test NOP (read mode) - read R0
		// ============================================================
		ui_in = {2'b00, 2'b00, OP_NOP};  // Read R0
		#10;
		$display("%0t | NOP    | R0   | -    | %h", $time, uo_out);

		// ============================================================
		// Test NOP (read mode) - read R1
		// ============================================================
		ui_in = {2'b01, 2'b01, OP_NOP};  // Read R1
		#10;
		$display("%0t | NOP    | R1   | -    | %h", $time, uo_out);

		$display("========================================");
		$display("=== Testbench Complete ===");
		$display("========================================");
		$finish;
	end

endmodule
