//
// scandoubler.v
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
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

// TODO: Delay vsync one line

// AMR - generates and output a pixel clock with a reliable phase relationship with
// with the scandoubled hsync pulse.  Allows the incoming data to be sampled more
// sparsely, reducing block RAM usage.  ce_x1/x2 are replaced with a ce_divider
// which is the largest value the counter will reach before resetting - so 3'111 to
// divide clk_sys by 8, 3'011 to divide by 4, 3'101 to divide by six.

// Also now has a bypass mode, in which the incoming data will be scaled to the output
// width but otherwise unmodified.  Simplifies the rest of the video chain.


module scandoubler
(
	// system interface
	input            clk_sys,

	input            bypass,

	// Pixelclock 
	input      [2:0] ce_divider,
	output           pixel_ena,

	// scanlines (00-none 01-25% 10-50% 11-75%)
	input      [1:0] scanlines,

	// shifter video interface
	input            hs_in,
	input            vs_in,
	input      [COLOR_DEPTH-1:0] r_in,
	input      [COLOR_DEPTH-1:0] g_in,
	input      [COLOR_DEPTH-1:0] b_in,

	// output interface
	output       hs_out,
	output       vs_out,
	output [5:0] r_out,
	output [5:0] g_out,
	output [5:0] b_out
);

parameter HCNT_WIDTH = 9; // Resolution of scandoubler buffer
parameter HSCNT_WIDTH = 12; // Resolution of hsync counters
parameter COLOR_DEPTH = 6; // Bits per colour to be stored in the buffer

// --------------------- create output signals -----------------
// latch everything once more to make it glitch free and apply scanline effect
reg scanline;
reg [5:0] r;
reg [5:0] g;
reg [5:0] b;

wire [5:0] r_o;
wire [5:0] g_o;
wire [5:0] b_o;
reg hs_o;
reg vs_o;

wire [COLOR_DEPTH*3-1:0] sd_mux = bypass ? {r_in, g_in, b_in} : sd_out;

always @(*) begin
	if (COLOR_DEPTH == 6) begin
		b = sd_mux[5:0];
		g = sd_mux[11:6];
		r = sd_mux[17:12];
	end else if (COLOR_DEPTH == 2) begin
		b = {3{sd_mux[1:0]}};
		g = {3{sd_mux[3:2]}};
		r = {3{sd_mux[5:4]}};
	end else if (COLOR_DEPTH == 1) begin
		b = {6{sd_mux[0]}};
		g = {6{sd_mux[1]}};
		r = {6{sd_mux[2]}};
	end else begin
		b = { sd_mux[COLOR_DEPTH-1:0], sd_mux[COLOR_DEPTH-1 -:(6-COLOR_DEPTH)] };
		g = { sd_mux[COLOR_DEPTH*2-1:COLOR_DEPTH], sd_mux[COLOR_DEPTH*2-1 -:(6-COLOR_DEPTH)] };
		r = { sd_mux[COLOR_DEPTH*3-1:COLOR_DEPTH*2], sd_mux[COLOR_DEPTH*3-1 -:(6-COLOR_DEPTH)] };
	end
end


reg [12:0] r_mul;
reg [12:0] g_mul;
reg [12:0] b_mul;

wire scanline_bypass = (!scanline) | (!(|scanlines)) | bypass;

// More subtle variant of the scanlines effect.
// 0 00 -> 1000000 0x40	 -  bypass / inert mode
// 1 01 -> 0111010 0x3a  -  25%
// 2 10 -> 0101110 0x2e  -  50%
// 3 11 -> 0011010 0x1a  -  75%

wire [6:0] scanline_coeff = scanline_bypass ?
				7'b1000000 : {~(&scanlines),scanlines[0],1'b1,~scanlines[0],2'b10};

always @(posedge clk_sys) begin
	if(ce_x2) begin
		hs_o <= hs_sd;
		vs_o <= vs_in;

		// reset scanlines at every new screen
		if(vs_o != vs_in) scanline <= 0;

		// toggle scanlines at begin of every hsync
		if(hs_o && !hs_sd) scanline <= !scanline;

		r_mul<=r*scanline_coeff;
		g_mul<=g*scanline_coeff;
		b_mul<=b*scanline_coeff;
	end
end

assign r_o = r_mul[11:6];
assign g_o = g_mul[11:6];
assign b_o = b_mul[11:6];


// Output multiplexing

assign r_out = bypass ? r_in : r_o;
assign g_out = bypass ? g_in : g_o;
assign b_out = bypass ? b_in : b_o;
assign hs_out = bypass ? hs_in : hs_o;
assign vs_out = bypass ? vs_in : vs_o;

assign pixel_ena = bypass ? ce_x1 : ce_x2;


// scan doubler output register
reg [COLOR_DEPTH*3-1:0] sd_out;

// ==================================================================
// ======================== the line buffers ========================
// ==================================================================

// 2 lines of 2**HCNT_WIDTH pixels 3*COLOR_DEPTH bit RGB
(* ramstyle = "no_rw_check" *) reg [COLOR_DEPTH*3-1:0] sd_buffer[2*2**HCNT_WIDTH];

// use alternating sd_buffers when storing/reading data   
reg        line_toggle;

// total hsync time (in 16MHz cycles), hs_total reaches 1024
reg  [HCNT_WIDTH-1:0] hcnt;
reg  [HSCNT_WIDTH:0] hs_max;
reg  [HSCNT_WIDTH:0] hs_rise;
reg  [HSCNT_WIDTH:0] synccnt;

// Input pixel clock, aligned with input sync:

reg [2:0] ce_divider_in;
reg [2:0] ce_divider_out;

reg [2:0] i_div;
wire ce_x1 = (i_div == ce_divider_in);

always @(posedge clk_sys) begin
	reg hsD, vsD;

	// Pixel logic on x1 clkena
	if(ce_x1) begin
		hcnt <= hcnt + 1'd1;
		sd_buffer[{line_toggle, hcnt}] <= {r_in, g_in, b_in};
	end

	// Generate pixel clock
	i_div <= i_div + 1'd1;

	if (i_div==ce_divider) i_div <= 3'b000;

	synccnt <= synccnt + 1'd1;
	hsD <= hs_in;
	if(hsD && !hs_in) begin
		// At hsync latch the ce_divider counter limit for the input clock
		// and pass the previous input clock limit to the output stage.
		// This should give correct output if the pixel clock changes mid-screen.
		ce_divider_out <= ce_divider_in;
		ce_divider_in <= ce_divider;
		hs_max <= {1'b0,synccnt[HSCNT_WIDTH:1]};
		hcnt <= 0;
		synccnt <= 0;
		i_div <= 3'b000;
	end

	// save position of rising edge
	if(!hsD && hs_in) hs_rise <= {1'b0,synccnt[HSCNT_WIDTH:1]};

	// begin of incoming hsync
	if(hsD && !hs_in) line_toggle <= !line_toggle;

	vsD <= vs_in;
	if(vsD != vs_in) line_toggle <= 0;

end

// ==================================================================
// ==================== output timing generation ====================
// ==================================================================

reg  [HSCNT_WIDTH:0] sd_synccnt;
reg  [HCNT_WIDTH-1:0] sd_hcnt;
reg        hs_sd;

// Output pixel clock, aligned with output sync:
reg [2:0] sd_i_div;
wire ce_x2 = (sd_i_div == ce_divider_out) | (sd_i_div == {1'b0,ce_divider_out[2:1]});

// timing generation runs 32 MHz (twice the input signal analysis speed)
always @(posedge clk_sys) begin
	reg hsD;

	// Output logic on x2 clkena
	if(ce_x2) begin
		// output counter synchronous to input and at twice the rate
		sd_hcnt <= sd_hcnt + 1'd1;
		
		// read data from line sd_buffer
		sd_out <= sd_buffer[{~line_toggle, sd_hcnt}];
	end
	
	
	//  Framing logic on sysclk
	sd_synccnt <= sd_synccnt + 1'd1;
	hsD <= hs_in;
	if(hsD && !hs_in) sd_synccnt <= hs_max;
	
	if(sd_synccnt == hs_max) begin
		sd_synccnt <= 0;
		sd_hcnt <= 0;
	end

	sd_i_div <= sd_i_div + 1'd1;
	if (sd_i_div==ce_divider) sd_i_div <= 3'b000;

	// replicate horizontal sync at twice the speed
	if(sd_synccnt == 0) begin
		hs_sd <= 0;
		sd_i_div <= 3'b000;
	end
	
	if(sd_synccnt == hs_rise) hs_sd <= 1;

end

endmodule
