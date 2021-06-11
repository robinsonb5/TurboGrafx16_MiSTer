//
// sdram.v
//
// sdram controller implementation for the MiST board
// https://github.com/mist-devel/mist-board
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
// Copyright (c) 2019 Gyorgy Szombathelyi
// Copyright (c) 2021 Alastair M. Robinson
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

// The following macros must be defined externally to describe the SDRAM chip:
// SDRAM_ROWBITS <13 in most cases>
// SDRAM_COLBITS <9 for 32 meg chips, 10 for 64 meg chips.>
// SDRAM_CL <2 or 3>
// SDRAM_tCKminCL2 <shortest cycle time allowed for CL2>
// SDRAM_tRC <Ref/Act to Ref/Act in ps>
// SDRAM_tWR <write recovery time in cycles>
// SDRAM_tRP <precharge time in ps>
//
// SDRAM_tCK <cycle time in ps> must be supplied as a parameter
// (Because it's project-specific, not board-specific.)
// If the core has a variable clock, specify the fastest rate.

module sdram_amr #(parameter SDRAM_tCK) (
	// interface to the MT48LC16M16 chip
	inout  [15:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output reg [`SDRAM_ROWBITS-1:0] SDRAM_A,    // 13 bit multiplexed address bus
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
	output reg [15:0] vram0_dout,
	input             vram0_we,

	input             vram1_req,
	output reg        vram1_ack,
	input      [15:1] vram1_addr,
	input      [15:0] vram1_din,
	output reg [15:0] vram1_dout,
	input             vram1_we,

	input      [16:0] aram_addr,
	input       [7:0] aram_din,
	output reg [15:0] aram_dout,
	input             aram_req,
	output reg        aram_req_ack,
	input             aram_we
);

localparam BANK_DELAY = ((`SDRAM_tRC+(SDRAM_tCK-1))/SDRAM_tCK)-2; // tRC-2 in cycles (rounded up)
localparam BANK_WRITE_DELAY = ((`SDRAM_tRP+(SDRAM_tCK-1))/SDRAM_tCK)+`SDRAM_tWR; // tWR + tRP in cycles (rounded up)
localparam REFRESH_DELAY = ((`SDRAM_tRC+(SDRAM_tCK-1))/SDRAM_tCK)-1; // tRC-1 in cycles (rounded up)

`ifdef VERILATOR
initial begin
	if(SDRAM_tCK>=`SDRAM_tCKminCL2)
		$display("CL2 is allowed (max speed is %d)",1000000/`SDRAM_tCKminCL2);
	else if(`SDRAM_CL==2) begin
		$display("CL2 not allowed at %d MHz (max speed is %d)",1000000/SDRAM_tCK,1000000/`SDRAM_tCKminCL2);
		$stop;
	end
end
`endif

// RAM configuration

localparam BURST_LENGTH   = 3'b000; // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY = 3'd`SDRAM_CL; // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 


// Refresh logic

// 64ms/8192 rows = 7.8us -> 842 cycles@108MHz
localparam RFRSH_CYCLES = 11'd842;
reg        refresh = 1'b0;
reg [10:0] refresh_cnt = 11'b0;
reg need_refresh;
always @(posedge clk)
	need_refresh <= (refresh_cnt >= RFRSH_CYCLES);

// We don't synchronise to the host core except with regard to refresh cycles,
// which must be timed so as not to delay a VRAM access.
// We supply a four-cycle window beginning shortly after clkref drops, during
// which refresh may begin.

reg clkref_d3;
reg clkref_d2;
reg clkref_d;
reg [2:0] refreshwindow;

always@(posedge clk) begin
	clkref_d3<=clkref;
	clkref_d2<=clkref_d3;
	clkref_d<=clkref_d2;
	if(clkref_d && !clkref_d2)
			refreshwindow<=3'b000;
	if(!blockrefresh)
		refreshwindow<=refreshwindow+1'b1;
end

wire blockrefresh = refreshwindow[2];


// RAM control signals

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
reg  [1:0] sd_dqm;
reg [15:0] sd_din;

// drive control signals according to current command
assign SDRAM_nCS  = sd_cmd[3];
assign SDRAM_nRAS = sd_cmd[2];
assign SDRAM_nCAS = sd_cmd[1];
assign SDRAM_nWE  = sd_cmd[0];
assign SDRAM_DQMH = sd_dqm[1];
assign SDRAM_DQML = sd_dqm[0];


// We use a multi-stage access pipeline like so:

// Read cycle - CL2, burst 1:
// |     RAS     |     CAS     |     MASK    |    LATCH    |     RAS     |     CAS     | ....
// | Act  | .... | .... | Read | .... | .... | .... | Ltch | Act  | .... | .... | Read | .... 
//                                            <chip><high z>
//                                                  < din reg'd >
//                                                         <data to port>

// Read cycle - CL3, burst 1:
// |     RAS     |     CAS     |     MASK    |    LATCH    |     ...     | RAS         |     CAS     | ....
// | Act  | .... | .... | Read | DQMs | .... | .... | .... | Ltch | .... | Act  | .... | .... | Read | .... 
//                                                   <chip><high z>
//                                                         < din reg'd >
//                                                                <data to port>

// Because RAS happens on even cycles, and CAS happens on odd cycles, reads to different banks
// can be overlapped - they just need to be 2 cycles apart:

// CL2

// |     RAS     |     CAS     |     MASK    |    LATCH    |     RAS     |     CAS     |
// | Act  | .... | .... | Read | .... | .... | .... | Ltch | Act  | .... | .... | Read | ....

// |     ...     |     RAS     |     CAS     |     MASK    |    LATCH    |     RAS     |
// | .... | .... | Act  | .... | .... | Read | .... | .... | .... | Ltch | Act  | .... | .... 

// |     ...     |     ...     |     RAS     |     CAS     |     MASK    |    LATCH    | ....
// | .... | .... | .... | .... | Act  | .... | .... | Read | .... | .... | .... | Ltch | Act  | .... |


// CL3

// |     RAS     |     CAS     |     MASK    |    LATCH    |     ...     |     RAS     |     CAS     
// | Act  | .... | .... | Read | DQMs | .... | .... | .... | Ltch | .... | Act  | .... | .... | Read 

// |     ...     |     RAS     |     CAS     |     MASK    |    LATCH    |     ...     |     RAS     
// | .... | .... | Act  | .... | .... | Read | DQMs | .... | .... | .... | Ltch | .... | Act  | .... 

// |     ...     |     ...     |     RAS     |     CAS     |     MASK    |    LATCH    |     ...     
// | .... | .... | .... | .... | Act  | .... | .... | Read | DQMs | .... | .... | .... | Ltch | .... 


// Data can be transferred on alternate cycles, until all four banks have been serviced.
// Read cycles in a single bank can be serviced every 8 cycles.

// Write cycles look like this:
// We use 2-word bursts, we invert the low address bit and mask off the first word, so the actual 
// write occurs one cycle after the Write command.  This gives a cycle's headroom to ensure
// there's no bus contention.

// |     RAS     |     CAS     |     MASK    |    LATCH    |     RAS     |     CAS     | ....
// | Act  | .... | .... | Writ | .... | .... | .... | .... | Act  | .... | .... | Writ | .... 


// Write cycles can't immediately follow read cycles; two slots must be left empty
// to avoid possible contention or mask clashes.

// Read to write cycle, CL2, Burst 1:

// |     RAS     |     CAS     |     MASK    |    LATCH    |     RAS     |     CAS     |
// | Act  | .... | .... | Read | .... | .... | .... | Ltch | Act  | .... | .... | Read | ....

// |     ...     |   (EMPTY)   |   (EMPTY)   |     RAS     |     CAS     |     MASK    |   
// | .... | .... | .... | .... | .... | .... | Act  | .... | .... | Writ | .... | .... | ....


// Read to write cycle, CL3, Burst 1:

// |     RAS     |     CAS     |     MASK    |    LATCH    |     ...     |     RAS     |     
// | Act  | .... | .... | Read | DQMs | .... | .... | .... | Ltch | .... | ACT  | .... | .... 

// |     ...     |   (EMPTY)   |   (EMPTY)   |     RAS     |     CAS     |     MASK    |   
// | .... | .... | .... | .... | .... | .... | Act  | .... | .... | Writ | .... | .... | ....


// Write cycles can be followed immediately by either a read or a write cycle.



// Bank logic.
// We take a bank-oriented rather than port-oriented view of the requests to be serviced.

reg [3:0] bankactive;
reg [4:0] bankbusy [4];
wire [3:0] bankready;

assign bankready[0]=bankbusy[0][4];	// Aliases for convenience
assign bankready[1]=bankbusy[1][4];
assign bankready[2]=bankbusy[2][4];
assign bankready[3]=bankbusy[3][4];


// Request handling and priority encoding

localparam PORT_NONE   = 4'd0;
localparam PORT_ROM    = 4'd1;
localparam PORT_WRAM   = 4'd2;
localparam PORT_VRAM0  = 4'd3;
localparam PORT_VRAM1  = 4'd4;
localparam PORT_ARAM   = 4'd5;

reg [3:0] bankreq;
reg [3:0] bankstate;
reg [3:0] bankwr;
reg [15:0] bankwrdata[4];
reg [3:0] bankport[4];
reg [22:1] bankaddr[4];
reg [1:0] bankdqm[4];


// Bank 0 priority encoder - WRAM / ARAM
always @(posedge clk) begin
	if (wram_req ^ port_state[PORT_WRAM]) begin
		bankreq[0]=1'b1;
		bankstate[0]=wram_req;
		bankport[0]=PORT_WRAM;
		bankdqm[0]=wram_we ? { ~wram_addr[0], wram_addr[0] } : 2'b11;
		bankaddr[0]={1'b1,wram_addr[21:1]};
		bankwr[0]=wram_we;
		bankwrdata[0]={wram_din,wram_din};
	end else if (aram_req ^ port_state[PORT_ARAM]) begin
		bankreq[0]= 1'b1;
		bankstate[0]=aram_req;
		bankport[0]=PORT_ARAM;
		bankdqm[0]=aram_we ? { ~aram_addr[0], aram_addr[0] } : 2'b11;
		bankaddr[0]={6'b000001,aram_addr[16:1]};
		bankwr[0]=aram_we;
		bankwrdata[0]={aram_din,aram_din};
	end else begin
		bankreq[0]=1'b0;
		// Just to avoid creating latches
		bankwr[0]=1'b0;
		bankstate[0]=wram_req;
		bankdqm[0]=wram_we ? { ~wram_addr[0], wram_addr[0] } : 2'b11;
		bankaddr[0]={1'b1, wram_addr[21:1]};
		bankwr[0]=wram_we;
		bankwrdata[0]={wram_din,wram_din};
		bankport[0]=PORT_NONE;
	end
end


// ROM has Bank 1 to itself
always @(posedge clk) begin
	bankreq[1]=rom_req ^ port_state[PORT_ROM];
	bankstate[1]=rom_req;
	bankport[1]=PORT_ROM;
	bankaddr[1]={1'b0,rom_addr[21:1]};
	bankdqm[1]={!rom_we,!rom_we};
	bankwr[1]=rom_we;
	bankwrdata[1]=rom_din;
end

// VRAM0 occupies Bank 2
always @(posedge clk) begin
	bankreq[2]=vram0_req ^ port_state[PORT_VRAM0];
	bankstate[2]=vram0_req;
	bankport[2]=PORT_VRAM0;
	bankaddr[2]={7'b0000000,vram0_addr};
	bankwr[2]=vram0_we;
	bankwrdata[2]=vram0_din;
	bankdqm[2]={!vram0_we,!vram0_we};
end

// VRAM1 occupies Bank 3
always @(posedge clk) begin
	bankreq[3]=vram1_req ^ port_state[PORT_VRAM1];
	bankstate[3]=vram1_req;
	bankport[3]=PORT_VRAM1;
	bankaddr[3]={7'b0000000,vram1_addr};
	bankwr[3]=vram1_we;
	bankwrdata[3]=vram1_din;
	bankdqm[3]={!vram1_we,!vram1_we};
end


// Keep track of when a write cycle is allowed.
// We can only write if the prevous 2 RAS slots weren't reads.

reg [1:0] readcycles;


// If VRAM wants to write we reserve a slot;
// other ports have to wait for the bus to be idle.

reg writepending;
always @(posedge clk) begin
	writepending <= (vram0_we & (vram0_req ^ port_state[PORT_VRAM0]))
			| (vram1_we & (vram1_req ^ port_state[PORT_VRAM1]));
end

wire writeblocked = |readcycles;
wire reservewrite = writepending & writeblocked;

reg port_state[10];


// RAS stage

// Command variables required for CAS

reg [1:0] ras_ba;
reg [8:0] ras_casaddr;
reg ras_wr;
reg [15:0] ras_wrdata;
reg [1:0] ras_dqm;
reg [3:0] ras1_port;
reg ras1_act;
reg [3:0] ras2_port;
reg ras2_act;

// Cas stage

reg [3:0] cas1_port;
reg cas1_act;
reg [3:0] cas2_port;

reg [1:0] cas_ba;
reg [`SDRAM_ROWBITS-1:0] cas_addr;
reg cas_wr;
reg [15:0] cas_wrdata;
reg [1:0] cas_dqm;

// Mask stage

reg [3:0] mask1_port;
reg [3:0] mask2_port;
reg mask_wr;
reg [15:0] mask_wrdata;
reg [1:0] mask_dqm;

// Latch stage

reg [3:0] latch1_port;
reg [3:0] latch2_port;

integer loopvar;

reg [15:0] dq_reg;
reg drive_dq;
`ifdef VERILATOR
assign SDRAM_DQ = drive_dq ? dq_reg : 16'bzzzzzzzzzzzzzzzz;
`else
assign SDRAM_DQ = dq_reg;
`endif

reg init = 1'b1;
reg [4:0] reset;

always @(posedge clk,negedge init_n) begin

	if(!init_n) begin
		sd_cmd<=CMD_INHIBIT;
		port_state[0]<=1'b0;
		port_state[1]<=1'b0;
		port_state[2]<=1'b0;
		port_state[3]<=1'b0;
		port_state[4]<=1'b0;
		port_state[5]<=1'b0;
		port_state[6]<=1'b0;
		port_state[7]<=1'b0;
		port_state[8]<=1'b0;
		port_state[9]<=1'b0;
		bankbusy[0]<=5'h7;
		bankbusy[1]<=5'h1f;
		bankbusy[2]<=5'h1f;
		bankbusy[3]<=5'h1f;
		init<=1'b1;
		reset<=5'd31;
	end else begin

		refresh_cnt <= refresh_cnt + 1'd1;

		for(loopvar=0; loopvar<4; loopvar=loopvar+1) begin
			if(!bankready[loopvar])
				bankbusy[loopvar]<=bankbusy[loopvar]-4'b1;
		end

`ifndef VERILATOR
		dq_reg<=16'bZZZZZZZZZZZZZZZZ;
//		SDRAM_DQ<=16'bZZZZZZZZZZZZZZZZ;
`endif

		SDRAM_A <= cas_addr; // Autoprecharge
		
		if(init) begin
			// initialization takes place at the end of the reset phase
			sd_cmd<=CMD_INHIBIT;
			if(bankready[0]) begin

				if(reset == 16) begin
					cas_addr[10]<=1'b1;	// Precharge all banks - set in advance to reduce address mux
				end

				if(reset == 15) begin
					sd_cmd <= CMD_PRECHARGE;
//					SDRAM_A[10] <= 1'b1;      // precharge all banks
				end

				if(reset == 10 || reset == 8) begin
					sd_cmd <= CMD_AUTO_REFRESH;
					cas_addr <= MODE;	// Put the mode on the address bus in advance of the command.
				end

				if(reset == 2) begin
					sd_cmd <= CMD_LOAD_MODE;
//					SDRAM_A <= MODE;
					SDRAM_BA <= 2'b00;
				end
				reset<=reset-1'b1;
				bankbusy[0]<=BANK_DELAY[4:0];
				if(reset==0)
				begin
					init<=1'b0;
					bankbusy[0]<=0;
				end
			end
		end else begin

			// Request dispatching

			drive_dq<=1'b0;
			sd_cmd<=CMD_INHIBIT;
			sd_dqm<=2'b11;
			// RAS stage
			ras1_port<=PORT_NONE;
			ras1_act<=1'b0;
			ras2_port<=ras1_port;
			ras2_act<=ras1_act;

			if(!ras1_act && !cas1_act) begin // Pick a bank and dispatch the command
				readcycles<={1'b0,readcycles[1]};
				ras_wr<=1'b0;
				ras_dqm<=2'b11;
				
				// First check and initiate refresh cycles if necessary.

				// FIXME should really have some way to force refreshes rather than 
				// waiting for the bus to be idle.
				if(!(&bankreq) && need_refresh && (&bankready) & !blockrefresh) begin
					sd_cmd<=CMD_AUTO_REFRESH;
					refresh_cnt<=0;
					bankbusy[0]<=REFRESH_DELAY[4:0];
					bankbusy[1]<=REFRESH_DELAY[4:0];
					bankbusy[2]<=REFRESH_DELAY[4:0];
					bankbusy[3]<=REFRESH_DELAY[4:0];
				end else if(!reservewrite) begin
					// VRAM ports have priority
					if(bankreq[2] && bankready[2] && (!writepending || bankwr[2]) && !(writeblocked && bankwr[2])) begin
						readcycles[1]<=~bankwr[2];
						port_state[bankport[2]]<=bankstate[2];
						bankbusy[2]<=BANK_DELAY[4:0];
						ras_ba<=2'b10;
						ras_casaddr<=bankaddr[2][`SDRAM_COLBITS:1];
						ras_wr<=bankwr[2];
						ras_wrdata<=bankwrdata[2];
						ras_dqm<=bankdqm[2];
						ras1_port<=bankport[2];
						ras1_act<=1'b1;

						sd_cmd<=CMD_ACTIVE;
						SDRAM_A <= bankaddr[2][`SDRAM_ROWBITS+`SDRAM_COLBITS:`SDRAM_COLBITS+1];
						SDRAM_BA <= 2'b10;
					end else if(bankreq[3] && bankready[3] && (!writepending || bankwr[3]) && !(writeblocked && bankwr[3])) begin
						readcycles[1]<=~bankwr[3];
						port_state[bankport[3]]<=bankstate[3];
						bankbusy[3]<=BANK_DELAY[4:0];
						ras_ba<=2'b11;
						ras_casaddr<=bankaddr[3][`SDRAM_COLBITS:1];
						ras_wr<=bankwr[3];
						ras_wrdata<=bankwrdata[3];
						ras_dqm<=bankdqm[3];
						ras1_port<=bankport[3];
						ras1_act<=1'b1;

						sd_cmd<=CMD_ACTIVE;
						SDRAM_A <= bankaddr[3][`SDRAM_ROWBITS+`SDRAM_COLBITS:`SDRAM_COLBITS+1];
						SDRAM_BA <= 2'b11;
					end else if(bankreq[0] && bankready[0] && (!writepending || bankwr[0]) && !(writeblocked && bankwr[0])) begin
						readcycles[1]<=~bankwr[0];
						port_state[bankport[0]]<=bankstate[0];
						bankbusy[0]<=BANK_DELAY[4:0];
						ras_ba<=2'b00;
						ras_casaddr<=bankaddr[0][`SDRAM_COLBITS:1];
						ras_wr<=bankwr[0];
						ras_wrdata<=bankwrdata[0];
						ras_dqm<=bankdqm[0];
						ras1_port<=bankport[0];
						ras1_act<=1'b1;

						sd_cmd<=CMD_ACTIVE;
						SDRAM_A <= bankaddr[0][`SDRAM_ROWBITS+`SDRAM_COLBITS:`SDRAM_COLBITS+1];
						SDRAM_BA <= 2'b00;
					end else if(bankreq[1] && bankready[1] && (!writepending || bankwr[1]) && !(writeblocked && bankwr[1])) begin
						readcycles[1]<=~bankwr[1];
						port_state[bankport[1]]<=bankstate[1];
						bankbusy[1]<=BANK_DELAY[4:0];
						ras_ba<=2'b01;
						ras_casaddr<=bankaddr[1][`SDRAM_COLBITS:1];
						ras_wr<=bankwr[1];
						ras_wrdata<=bankwrdata[1];
						ras_dqm<=bankdqm[1];
						ras1_port<=bankport[1];
						ras1_act<=1'b1;

						sd_cmd<=CMD_ACTIVE;
						SDRAM_A <= bankaddr[1][`SDRAM_ROWBITS+`SDRAM_COLBITS:`SDRAM_COLBITS+1];
						SDRAM_BA <= 2'b01;
					end
				end
			end

			if(ras2_port != PORT_NONE) begin 
				cas_addr<={`SDRAM_ROWBITS{1'b0}};
				cas_addr[10]<=1'b1; // Auto-precharge
				cas_addr[`SDRAM_COLBITS-1:0]<=ras_casaddr;
				cas_wr<=ras_wr;
				cas_dqm<=ras_dqm;
				cas_wrdata<=ras_wrdata;
				cas_ba<=ras_ba;
			end
			cas1_port<=ras2_port;
			cas1_act<=ras2_act;

		// CAS stage

			if(cas1_port != PORT_NONE) begin 
				// Action the CAS command, if any
				SDRAM_BA <= cas_ba;
//				SDRAM_A <= {4'b0010,cas_addr}; // Autoprecharge
				if(cas_wr) begin
					sd_cmd<=CMD_WRITE;
					bankbusy[cas_ba]<=BANK_WRITE_DELAY[4:0];
`ifdef VERILATOR
					drive_dq<=1'b1;
`endif
//					SDRAM_DQ<=cas_wrdata;
					dq_reg <= cas_wrdata;
					sd_dqm<=cas_dqm;
				end else begin
					sd_cmd<=CMD_READ;
					sd_dqm<=2'b00; // Enable DQs for first word of a read, if any
				end
			end

			cas2_port<=cas1_port;

			if(cas2_port!=PORT_NONE && !cas_wr)	// Enable DQs for reads if CL3
				sd_dqm<=2'b00;

			// Pump the pipeline.  Write cycles finish here, read cycles continue.

			if(`SDRAM_CL==2) begin
				mask2_port<=mask_wr ? PORT_NONE : cas2_port;
				mask_wr<=cas_wr;
				mask_wrdata<=cas_wrdata;
				mask_dqm<=cas_dqm;
			end else begin
				mask1_port<=cas2_port;
				mask_wr<=cas_wr;
				mask_wrdata<=cas_wrdata;
				mask_dqm<=cas_dqm;

				mask2_port<=mask_wr ? PORT_NONE : mask1_port;
			end
			// Latch stage

			latch1_port<=mask2_port;
		end
	end
end


// Acknowledge requests

reg [15:0] vram0_dout_r;
reg [15:0] vram1_dout_r;
assign vram0_dout=latch2_port == PORT_VRAM0 ? sd_din : vram0_dout_r;
assign vram1_dout=latch2_port == PORT_VRAM1 ? sd_din : vram1_dout_r;

always @(posedge clk, negedge init_n) begin

	if(!init_n) begin
		rom_req_ack <= 1'b0;
		wram_req_ack <= 1'b0;
		vram0_ack <= 1'b0;
		vram1_ack <= 1'b0;
		aram_req_ack <= 1'b0;
	end else begin

		sd_din<=SDRAM_DQ;

		// Acknowledge writes
		// We also mirror the port inputs to outputs here.
		// (Required for some TGfx16 games)
		if(ras_wr) begin
			case (ras2_port)
				PORT_ROM:   rom_req_ack <= rom_req;
				PORT_WRAM:  begin 
					wram_req_ack <= wram_req;
					if (wram_we) begin
						if (wram_addr[0])
							wram_dout[15:8] <= wram_din;
						else
							wram_dout[7:0] <= wram_din;
					end
				end
				PORT_VRAM0: begin
					vram0_ack <= vram0_req;
					vram0_dout_r <= vram0_din;
				end
				PORT_VRAM1: begin
					vram1_ack <= vram1_req;
					vram1_dout_r <= vram1_din;
				end
				PORT_ARAM:  begin 
					aram_req_ack <= aram_req;
					if (aram_we) begin
						if (aram_addr[0])
							aram_dout[15:8] <= aram_din;
						else
							aram_dout[7:0] <= aram_din;
					end
				end
				default: ;
			endcase
		end

		// Early ack for READs (writes acked anyway, so no need to bother filtering them out.)
		if(`SDRAM_CL==2) begin			case (ras1_port)
				PORT_VRAM0: vram0_ack <= vram0_req;
				PORT_VRAM1: vram1_ack <= vram1_req;
				default: ;
			endcase
		end else begin
			case (ras2_port)
				PORT_VRAM0: vram0_ack <= vram0_req;
				PORT_VRAM1: vram1_ack <= vram1_req;
				default: ;
			endcase
		end
		latch2_port<=latch1_port;

		case (latch2_port)
			PORT_ROM:   begin rom_dout    <= sd_din; rom_req_ack <= rom_req;   end
			PORT_WRAM:  begin wram_dout   <= sd_din; wram_req_ack <= wram_req; end
			PORT_VRAM0: begin vram0_dout_r  <= sd_din; end // vram0_ack <= vram0_req;   end // Ack'ed early
			PORT_VRAM1: begin vram1_dout_r  <= sd_din; end // vram1_ack <= vram1_req;   end // Ack'ed early
			PORT_ARAM:  begin aram_dout   <= sd_din; aram_req_ack <= aram_req; end
			default: ;
		endcase
	end
end

endmodule
