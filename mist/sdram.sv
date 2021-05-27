//
// sdram.v
//
// sdram controller implementation for the MiST board
// https://github.com/mist-devel/mist-board/wiki
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
// Copyright (c) 2019 Gyorgy Szombathelyi
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module sdram (

	// interface to the MT48LC16M16 chip
	inout  reg [15:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output     [12:0] SDRAM_A,    // 13 bit multiplexed address bus
	output reg        SDRAM_DQML, // two byte masks
	output reg        SDRAM_DQMH, // two byte masks
	output reg [1:0]  SDRAM_BA,   // two banks
	output            SDRAM_nCS,  // a single chip select
	output            SDRAM_nWE,  // write enable
	output            SDRAM_nRAS, // row address select
	output            SDRAM_nCAS, // columns address select

	// cpu/chipset interface
	input             init_n,     // init signal after FPGA config to initialize RAM
	input             clk,        // sdram clock
	input             clkref,
	input             sync_en,

	input      [15:0] rom_din,
	output reg [15:0] rom_dout,
	input      [21:1] rom_addr,
	input             rom_req,
	output reg        rom_req_ack,
	input             rom_we,
	
	input      [21:0] wram_addr,
	input       [7:0] wram_din,
	output reg [15:0] wram_dout,
	input             wram_req,
	output reg        wram_req_ack,
	input             wram_we,

	input             vram0_req,
	output reg        vram0_ack,
	input      [15:1] vram0_addr,
	input      [15:0] vram0_din,
	output     [15:0] vram0_dout,
	input             vram0_we,

	input             vram1_req,
	output reg        vram1_ack,
	input      [15:1] vram1_addr,
	input      [15:0] vram1_din,
	output     [15:0] vram1_dout,
	input             vram1_we,

	input      [16:0] aram_addr,
	input       [7:0] aram_din,
	output reg [15:0] aram_dout,
	input             aram_req,
	output reg        aram_req_ack,
	input             aram_we
);

localparam RASCAS_DELAY   = 3'd3;   // tRCD=20ns -> 3 cycles@128MHz
localparam BURST_LENGTH   = 3'b000; // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd3;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 
// 64ms/8192 rows = 7.8us -> 1000 cycles@128MHz
localparam RFRSH_CYCLES = 10'd1000;

// ---------------------------------------------------------------------
// ------------------------ sdram state machine ------------------------
// ---------------------------------------------------------------------

// SDRAM state machine for 3 bank interleaved access
//CL3
//0 RAS0                        DS2
//1           DATA1 available
//2           RAS1
//3 CAS0                        DATA2 available
//4 DS0                         RAS2
//5           CAS1
//6           DS1
//7 DATA0                       CAS2

// 12 cycle state machine to keep in sync with hi-res dotclock
// 0 RAS0
// 1
// 2           RAS1
// 3 CAS0
// 4 DS0                         RAS2
// 5           CAS1
// 6           DS1
// 7 DATA0                       CAS2
// 8                             DS2
// 9           DATA1
//10
//11                             DATA2

wire [3:0] STATE_RAS0      = 4'd0;   // first state in cycle
wire [3:0] STATE_RAS1      = 4'd2;   // Second ACTIVE command after RAS0 + tRRD (15ns)
wire [3:0] STATE_RAS2      = 4'd4;   // Third ACTIVE command after RAS0 + tRRD (15ns)
wire [3:0] STATE_CAS0      = STATE_RAS0 + RASCAS_DELAY; // CAS phase - 3
wire [3:0] STATE_CAS1      = STATE_RAS1 + RASCAS_DELAY; // CAS phase - 5
wire [3:0] STATE_CAS2      = STATE_RAS2 + RASCAS_DELAY; // CAS phase - 7
wire [3:0] STATE_DS0       = STATE_CAS0 + 1'd1;
wire [3:0] STATE_READ0     = {sync_r, 3'd0};        //STATE_CAS0 + CAS_LATENCY + 2'd2;
wire [3:0] STATE_DS1       = STATE_CAS1 + 1'd1;
wire [3:0] STATE_READ1     = {sync_r, 3'd2};        //STATE_CAS1 + CAS_LATENCY + 2'd2;
wire [3:0] STATE_DS2       = {sync_r, 3'd0};        //STATE_CAS2 + 1'd1;
wire [3:0] STATE_READ2     = {1'b0, ~sync_r, 2'b00 };//? 4'd0 : 4'd4;  //STATE_CAS2 + CAS_LATENCY + 2'd2;
wire [3:0] STATE_LAST      = {sync_r, ~sync_r, 2'b11};//? 4'd11 : 4'd7; // last state in cycle

reg [3:0] t;
reg       sync_r;
reg       clkref_d;

always @(posedge clk) begin
	reg allow_refresh;

	clkref_d <= clkref;
	// allow refresh to start when a VRAM request is expected, but didn't get one
	allow_refresh <= ~clkref & clkref_d;

	case(t)
		4'h0: begin // RAS0
				t <= 4'h1;
				sync_r <= sync_en;
				// shortcut if no request is pending
				if (next_port[0] == PORT_NONE && ~|oe_latch[2:1] && ~|we_latch[2:1] && !refresh && !init && !sync_r) begin
					if (next_port[1] != PORT_NONE)
						t <= STATE_RAS1;
					else if (next_port[2] != PORT_NONE || (need_refresh && allow_refresh))
						t <= STATE_RAS2;
					else
						t <= STATE_RAS0;
				end
			end
		4'h1: t <= 4'h2;
		4'h2: begin // RAS1
				t <= 4'h3;
				// shortcut if no request is pending
				if (next_port[1] == PORT_NONE && ~oe_latch[0] && ~oe_latch[2] && ~we_latch[0] && ~we_latch[2] && !refresh && !init && !sync_r)
					t <= STATE_RAS2;
			end
		4'h3: t <= 4'h4;
		4'h4: begin // RAS2
				t <= 4'h5;
				// shortcut if no request is pending
				if (next_port[2] == PORT_NONE && ~|oe_latch[1:0] && ~|we_latch[1:0] && !need_refresh && !init && !sync_r)
					t <= STATE_RAS0;
			end
		4'h5: t <= 4'h6;
		4'h6: t <= 4'h7;
		4'h7: begin // LAST
				t <= 4'h8;
				if (!sync_r) t <= STATE_RAS0;
			end
		4'h8: t <= 4'h9;
		4'h9: t <= 4'ha;
		4'ha: t <= 4'hb;
		4'hb: if (~clkref_d & clkref) t <= STATE_RAS0;
	endcase

end

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// wait 1ms (32 8Mhz cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
reg [4:0]  reset;
reg        init = 1'b1;
always @(posedge clk,negedge init_n) begin
	if(!init_n) begin
		reset <= 5'h1f;
		init <= 1'b1;
	end else begin
		if((t == STATE_LAST) && (reset != 0)) reset <= reset - 5'd1;
		init <= !(reset == 0);
	end
end

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

reg  [3:0] sd_cmd;   // current command sent to sd ram
reg [12:0] sd_a;
reg [15:0] sd_din;

// drive control signals according to current command
assign SDRAM_nCS  = sd_cmd[3];
assign SDRAM_nRAS = sd_cmd[2];
assign SDRAM_nCAS = sd_cmd[1];
assign SDRAM_nWE  = sd_cmd[0];
assign SDRAM_A    = sd_a;

reg [24:0] addr_latch[3];
reg [15:0] din_latch[3], next_din[3];
reg  [2:0] oe_latch, next_oe;
reg  [2:0] we_latch, next_we;
reg  [1:0] ds[3], next_ds[3];

localparam PORT_NONE  = 2'd0;

localparam PORT_ROM   = 2'd1;
localparam PORT_WRAM  = 2'd2;

localparam PORT_VRAM  = 2'd1;
localparam PORT_ARAM  = 2'd2;

reg  [1:0] port[3];
reg  [1:0] next_port[3];
reg [24:0] next_addr[3];

reg [15:0] vram0_dout_reg;
reg [15:0] vram1_dout_reg;

reg        refresh;
reg [10:0] refresh_cnt;
reg        need_refresh = 1'b0;

reg        rom_req_state;
reg        wram_req_state;
reg        aram_req_state;

always @(posedge clk) begin

	if (refresh_cnt == 0)
		need_refresh <= 0;
	else if (refresh_cnt == RFRSH_CYCLES)
		need_refresh <= 1;

end

wire clkref_rise = ~clkref_d & clkref;
reg  clkref_rise_d;
always @(posedge clk) clkref_rise_d <= clkref_rise;

// ROM, RAM: bank 0
always @(*) begin
	next_port[0] = PORT_NONE;
	next_addr[0] = 0;
	{ next_oe[0], next_we[0] } = 0;
	next_ds[0] = 0;
	next_din[0] = 0;

	if (refresh || ((clkref_rise || clkref_rise_d) && !sync_r)) next_port[0] = PORT_NONE;
	else if (rom_req ^ rom_req_state) begin
		next_port[0] = PORT_ROM;
		next_addr[0] = { 3'b000, rom_addr, 1'b0 };
		{ next_oe[0], next_we[0] } = { ~rom_we, rom_we };
		next_ds[0] = 2'b11;
		next_din[0] = rom_din;
	end else if (wram_req ^ wram_req_state) begin
		next_port[0] = PORT_WRAM;
		next_addr[0] = { 3'b001, wram_addr };
		{ next_oe[0], next_we[0] } = { ~wram_we, wram_we };
		next_ds[0] = wram_we ? { wram_addr[0], ~wram_addr[0] } : 2'b11;
		next_din[0] = { wram_din, wram_din };
	end
end

// VRAM1: bank 2
always @(*) begin
	next_port[1] = PORT_NONE;
	next_addr[1] = 0;
	{ next_oe[1], next_we[1] } = 0;
	next_ds[1] = 0;
	next_din[1] = 0;

	if (refresh) next_port[1] = PORT_NONE;
	else if (vram1_req ^ vram1_ack) begin
		next_port[1] = PORT_VRAM;
		next_addr[1] = { 9'b100000000, vram1_addr, 1'b0 };
		{ next_oe[1], next_we[1] } = { ~vram1_we, vram1_we };
		next_ds[1] = 2'b11;
		next_din[1] = vram1_din;
	end	else if (aram_req ^ aram_req_state) begin
		next_port[1] = PORT_ARAM;
		next_addr[1] = { 8'b10000001, aram_addr };
		{ next_oe[1], next_we[1] } = { ~aram_we, aram_we };
		next_ds[1] = aram_we ? { aram_addr[0], ~aram_addr[0] } : 2'b11;
		next_din[1] = { aram_din, aram_din };
	end
end

// VRAM0: bank 3
always @(*) begin
	next_port[2] = PORT_NONE;
	next_addr[2] = 0;
	{ next_oe[2], next_we[2] } <= 0;
	next_ds[2] = 0;
	next_din[2] = 0;

	if (vram0_req ^ vram0_ack) begin
		next_port[2] = PORT_VRAM;
		next_addr[2] = { 9'b110000000, vram0_addr, 1'b0 };
		{ next_oe[2], next_we[2] } = { ~vram0_we, vram0_we };
		next_ds[2] = 2'b11;
		next_din[2] = vram0_din;
	end
end

always @(posedge clk) begin

	// permanently latch ram data to reduce delays
	sd_din <= SDRAM_DQ;
	SDRAM_DQ <= 16'bZZZZZZZZZZZZZZZZ;
	{ SDRAM_DQMH, SDRAM_DQML } <= 2'b11;
	sd_cmd <= CMD_INHIBIT;  // default: idle

	if(init) begin
		refresh <= 1'b0;
		refresh_cnt <= 0;

		// initialization takes place at the end of the reset phase
		if(t == STATE_RAS0) begin

			if(reset == 15) begin
				sd_cmd <= CMD_PRECHARGE;
				sd_a[10] <= 1'b1;      // precharge all banks
			end

			if(reset == 10 || reset == 8) begin
				sd_cmd <= CMD_AUTO_REFRESH;
			end

			if(reset == 2) begin
				sd_cmd <= CMD_LOAD_MODE;
				sd_a <= MODE;
				SDRAM_BA <= 2'b00;
			end
		end
	end else begin

		refresh_cnt <= refresh_cnt + 1'd1;

		// RAS phase
		// bank 0,1 - ROM, WRAM
		if(t == STATE_RAS0) begin
			port[0] <= next_port[0];
			addr_latch[0] <= next_addr[0];
			sd_a <= next_addr[0][22:10];
			SDRAM_BA <= next_addr[0][24:23];
			{ we_latch[0], oe_latch[0] } <= { next_we[0], next_oe[0] };
			din_latch[0] <= next_din[0];
			ds[0] <= next_ds[0];
			if (next_port[0] != PORT_NONE) sd_cmd <= CMD_ACTIVE;

			case (next_port[0])
			PORT_ROM:  rom_req_state <= rom_req;
			PORT_WRAM: begin
				wram_req_state <= wram_req;
				if (wram_we) if (next_addr[0][0]) wram_dout[15:8] <= wram_din; else wram_dout[7:0] <= wram_din;
			end

			default: ;

			endcase
		end

		// bank 2 - VRAM1
		if(t == STATE_RAS1) begin
			port[1] <= next_port[1];
			addr_latch[1] <= next_addr[1];
			sd_a <= next_addr[1][22:10];
			SDRAM_BA <= 2'b10;
			din_latch[1] <= next_din[1];
			{ we_latch[1], oe_latch[1] } <= { next_we[1], next_oe[1] };
			ds[1] <= next_ds[1];
			if (next_port[1] != PORT_NONE) sd_cmd <= CMD_ACTIVE;
			if (next_port[1] == PORT_ARAM) aram_req_state <= aram_req;
			if (next_port[1] == PORT_VRAM && vram1_we) vram1_dout_reg <= vram1_din;
		end

		// bank3 - VRAM0
		if(t == STATE_RAS2) begin
			refresh <= 1'b0;

			port[2] <= next_port[2];
			addr_latch[2] <= next_addr[2];
			sd_a <= next_addr[2][22:10];
			SDRAM_BA <= 2'b11;
			din_latch[2] <= next_din[2];
			{ we_latch[2], oe_latch[2] } <= { next_we[2], next_oe[2] };
			ds[2] <= next_ds[2];

			if (next_port[2] == PORT_VRAM && vram0_we) vram0_dout_reg <= vram0_din;
			if (next_port[2] != PORT_NONE) sd_cmd <= CMD_ACTIVE;
			else
				if (!we_latch[0] && !oe_latch[0] && !we_latch[1] && !oe_latch[1] && need_refresh) begin
					refresh <= 1'b1;
					refresh_cnt <= 0;
					sd_cmd <= CMD_AUTO_REFRESH;
				end
		end

		// CAS phase
		// ROM, WRAM
		if(t == STATE_CAS0 && (oe_latch[0] || we_latch[0])) begin
			sd_cmd <= we_latch[0]?CMD_WRITE:CMD_READ;
			if (we_latch[0]) begin
				SDRAM_DQ <= din_latch[0];
				{ SDRAM_DQMH, SDRAM_DQML } <= ~ds[0];
			end
			sd_a <= { 4'b0010, addr_latch[0][9:1] };  // auto precharge
			SDRAM_BA <= addr_latch[0][24:23];
		end
		if(we_latch[0] && t == STATE_CAS0) begin
			case (port[0])
				PORT_ROM:   rom_req_ack <= rom_req;
				PORT_WRAM:  wram_req_ack <= wram_req;
				default: ;
			endcase
		end

		// VRAM1/ARAM
		if(t == STATE_CAS1 && (oe_latch[1] || we_latch[1])) begin
			sd_cmd <= we_latch[1]?CMD_WRITE:CMD_READ;
			if (we_latch[1]) begin
				SDRAM_DQ <= din_latch[1];
				{ SDRAM_DQMH, SDRAM_DQML } <= ~ds[1];
			end
			sd_a <= { 4'b0010, addr_latch[1][9:1] };  // auto precharge
			SDRAM_BA <= 2'b10;
			case (port[1])
				PORT_VRAM: vram1_ack <= vram1_req;
				PORT_ARAM: aram_req_ack <= aram_req;
				default: ;
			endcase
		end

		// VRAM0
		if(t == STATE_CAS2 && (oe_latch[2] || we_latch[2])) begin
			sd_cmd <= we_latch[2]?CMD_WRITE:CMD_READ;
			if (we_latch[2]) begin
				SDRAM_DQ <= din_latch[2];
				{ SDRAM_DQMH, SDRAM_DQML } <= ~ds[2];
			end
			sd_a <= { 4'b0010, addr_latch[2][9:1] };  // auto precharge
			SDRAM_BA <= 2'b11;
			case (port[2])
				PORT_VRAM: vram0_ack <= vram0_req;
				default: ;
			endcase
		end

		// read phase
		// ROM, WRAM
		if(t == STATE_DS0 && oe_latch[0]) { SDRAM_DQMH, SDRAM_DQML } <= 2'b00;
		if(t == STATE_READ0 && oe_latch[0]) begin
			case (port[0])
				PORT_ROM:   begin rom_dout <= sd_din; rom_req_ack <= rom_req; end
				PORT_WRAM:  begin wram_dout <= sd_din; wram_req_ack <= wram_req; end
				default: ;
			endcase
		end

		// VRAM1
		if(t == STATE_DS1 && oe_latch[1]) { SDRAM_DQMH, SDRAM_DQML } <= 2'b00;
		if(t == STATE_READ1 && oe_latch[1]) begin
			case (port[1])
				PORT_VRAM: vram1_dout_reg <= sd_din;
				PORT_ARAM: aram_dout <= sd_din;
				default: ;
			endcase
		end

		// VRAM0
		if(t == STATE_DS2 && oe_latch[2]) { SDRAM_DQMH, SDRAM_DQML } <= 2'b00;
		if(t == STATE_READ2 && oe_latch[2]) begin
			case (port[2])
				PORT_VRAM: vram0_dout_reg <= sd_din;
				default: ;
			endcase
		end

	end
end

assign vram0_dout = (t == STATE_READ2 && oe_latch[2] && port[2] == PORT_VRAM) ? sd_din : vram0_dout_reg;
assign vram1_dout = (t == STATE_READ1 && oe_latch[1] && port[1] == PORT_VRAM) ? sd_din : vram1_dout_reg;

endmodule
