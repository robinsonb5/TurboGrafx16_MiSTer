//============================================================================
//  TGFX16 top-level for MiST
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module TGFX16_MIST_TOP
(
   input         CLOCK_27,   // Input clock 27 MHz

   output  [5:0] VGA_R,
   output  [5:0] VGA_G,
   output  [5:0] VGA_B,
   output        VGA_HS,
   output        VGA_VS,

   output        LED,

   output        AUDIO_L,
   output        AUDIO_R,

   input         UART_RX,

   input         SPI_SCK,
   input         SPI_DI,
   inout         SPI_DO,
   input         SPI_SS2,
   input         SPI_SS3,
   input         SPI_SS4,
   input         CONF_DATA0,

   output [12:0] SDRAM_A,
   inout  [15:0] SDRAM_DQ,
   output        SDRAM_DQML,
   output        SDRAM_DQMH,
   output        SDRAM_nWE,
   output        SDRAM_nCAS,
   output        SDRAM_nRAS,
   output        SDRAM_nCS,
   output  [1:0] SDRAM_BA,
   output        SDRAM_CLK,
   output        SDRAM_CKE
);

localparam LITE = 0;

assign LED  = ~ioctl_download & ~bk_ena;

`include "build_id.v"
parameter CONF_STR = {
	"TGFX16;;",
	"F,BINPCESGX,Load;",
//	"S,SAV,Mount;",
//	"TF,Write Save RAM;",
	"P1,Video options;",
	"P1O12,Scandoubler Fx,None,CRT 25%,CRT 50%,CRT 75%;",
	"P1O3,Overscan,Hidden,Visible;",
	"P1O4,Border Color,Original,Black;",
	"P2,Controllers;",
	"P2O8,Swap Joysticks,No,Yes;",
	"P2O9,Turbo Tap,Disabled,Enabled;",
	"P2OA,Controller,2 Buttons,6 Buttons;",
	"P2OB,Mouse,Disable,Enable;",
//	"OE,Arcade Card,Disabled,Enabled;",
	"T0,Reset;",
	"V,v1.0.",`BUILD_DATE
};

wire [1:0] scanlines = status[2:1];
wire       overscan = ~status[3];
wire       border = ~status[4];
wire       joy_swap = status[8];
wire       turbotap = status[9];
wire       buttons6 = status[10];
wire       mouse_en = status[11];
wire       bk_save = status[15];
wire       sgx = ioctl_index[7:6] == 2'b10;
wire       ac_en = 0;//status[14];

////////////////////   CLOCKS   ///////////////////

wire locked;
wire clk_sys, clk_mem;

pll pll
(
	.inclk0(CLOCK_27),
	.c0(SDRAM_CLK),
	.c1(clk_mem),
	.c2(clk_sys),
	.locked(locked)
);

reg reset;
always @(posedge clk_sys) begin
	reset <= buttons[1] | status[0] | ioctl_download;
end

//////////////////   MiST I/O   ///////////////////
wire [31:0] joy_a;
wire [31:0] joy_b;
wire [31:0] joy_2;
wire [31:0] joy_3;
wire [31:0] joy_4;

wire  [1:0] buttons;
wire [31:0] status;
wire        ypbpr;
wire        scandoubler_disable;
wire        no_csync;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wait;

wire  [8:0] mouse_x;
wire  [8:0] mouse_y;
wire  [7:0] mouse_flags;  // YOvfl, XOvfl, dy8, dx8, 1, mbtn, rbtn, lbtn
wire        mouse_strobe;

reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire        sd_buff_wr;
wire        sd_buff_rd;
wire        img_mounted;
wire [31:0] img_size;

user_io #(.STRLEN($size(CONF_STR)>>3)) user_io
(
	.clk_sys(clk_sys),
	.clk_sd(clk_sys),
	.SPI_SS_IO(CONF_DATA0),
	.SPI_CLK(SPI_SCK),
	.SPI_MOSI(SPI_DI),
	.SPI_MISO(SPI_DO),

	.conf_str(CONF_STR),

	.status(status),
	.scandoubler_disable(scandoubler_disable),
	.ypbpr(ypbpr),
	.no_csync(no_csync),
	.buttons(buttons),
	.joystick_0(joy_a),
	.joystick_1(joy_b),
	.joystick_2(joy_2),
	.joystick_3(joy_3),
	.joystick_4(joy_4),

	.mouse_x(mouse_x),
	.mouse_y(mouse_y),
	.mouse_flags(mouse_flags),
	.mouse_strobe(mouse_strobe),

	.sd_conf(1'b0),
	.sd_sdhc(1'b1),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_dout(sd_buff_dout),
	.sd_din(sd_buff_din),
	.sd_dout_strobe(sd_buff_wr),
	.sd_din_strobe(sd_buff_rd),
	.img_mounted(img_mounted),
	.img_size(img_size)
);

data_io data_io
(
	.clk_sys(clk_sys),
	.SPI_SCK(SPI_SCK),
	.SPI_DI(SPI_DI),
	.SPI_DO(SPI_DO),
	.SPI_SS2(SPI_SS2),
	.SPI_SS4(SPI_SS4),

	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index)
);

////////////////////////////  SDRAM  ///////////////////////////////////
wire        romhdr = ioctl_addr[9:0] == 10'h200; // has 512 byte header
wire [21:0] ROM_ADDR;
wire [21:1] rom_addr_rw = cart_download ? ioctl_addr[21:1] : ( ROM_ADDR[21:1] + { romhdr, 8'h0 } );
reg  [21:1] rom_addr_sd;
wire        ROM_RD;
wire  [7:0] ROM_Q = ROM_ADDR[0] ? rom_dout[15:8] : rom_dout[7:0];
wire [15:0] rom_dout;
reg         rom_req;
wire        rom_req_ack;

wire [21:0] WRAM_ADDR;
reg  [21:0] wram_addr_sd;
wire        WRAM_CE;
wire        WRAM_WR;
wire  [7:0] WRAM_Q = WRAM_ADDR[0] ? wram_dout[15:8] : wram_dout[7:0];
wire  [7:0] WRAM_D;
reg   [7:0] wram_din;
wire [15:0] wram_dout;
reg         wram_wrD;
wire        wram_req;
wire        wram_req_ack;

wire [19:0] BSRAM_ADDR;
reg  [19:0] bsram_sd_addr;
wire        BSRAM_CE_N;
wire        BSRAM_OE_N;
wire        BSRAM_WE_N;
wire        BSRAM_RD_N;
wire  [7:0] BSRAM_Q = BSRAM_ADDR[0] ? bsram_dout[15:8] : bsram_dout[7:0];
wire  [7:0] BSRAM_D;
reg   [7:0] bsram_din;
wire [15:0] bsram_dout;
wire        bsram_rd = ~BSRAM_CE_N & ~BSRAM_RD_N;
reg         bsram_rdD;
wire        bsram_wr = ~BSRAM_CE_N & ~BSRAM_WE_N;
reg         bsram_wrD;
wire        bsram_req;
reg         bsram_req_reg;

wire        VRAM_OE_N;

wire [16:1] VRAM0_ADDR;
reg  [15:1] vram0_addr_sd;
wire        VRAM0_RD;
wire        VRAM0_WE;
wire [15:0] VRAM0_D, VRAM0_Q;
reg  [15:0] vram0_din;
wire        vram0_req;
reg         vram0_weD;

wire [16:1] VRAM1_ADDR;
reg  [15:1] vram1_addr_sd;
wire        VRAM1_RD;
wire        VRAM1_WE;
wire [15:0] VRAM1_D, VRAM1_Q;
reg  [15:0] vram1_din;
wire        vram1_req;
reg         vram1_weD;

wire [16:0] ARAM_ADDR;
reg  [16:0] aram_addr_sd;
wire        ARAM_RD;
wire        ARAM_WR;
wire  [7:0] ARAM_Q = ARAM_ADDR[0] ? aram_dout[15:8] : aram_dout[7:0];
wire  [7:0] ARAM_D;
reg   [7:0] aram_din;
wire [15:0] aram_dout;
reg         aram_rd_last;
reg         aram_wr_last;
wire        aram_req;
wire        aram_req_reg;

reg         ioctl_wr_last;

always @(posedge clk_sys) begin

	ioctl_wr_last <= ioctl_wr;

	if ((~cart_download && ROM_RD && rom_addr_sd != rom_addr_rw) || ((ioctl_wr_last ^ ioctl_wr) & cart_download)) begin
		rom_req <= ~rom_req;
		rom_addr_sd <= rom_addr_rw;
	end

	wram_wrD <= WRAM_WR;
	if (WRAM_CE && ((WRAM_ADDR != wram_addr_sd) || (~wram_wrD & WRAM_WR))) begin
		wram_req <= ~wram_req;
		wram_addr_sd <= WRAM_ADDR;
		wram_din <= WRAM_D;
	end

	aram_wr_last <= ARAM_WR;
	aram_rd_last <= ARAM_RD;
	if ((ARAM_RD && ARAM_ADDR[15:1] != aram_addr_sd[15:1]) || (ARAM_WR && ARAM_ADDR != aram_addr_sd) || (ARAM_RD & ~aram_rd_last) || (ARAM_WR & ~aram_wr_last)) begin
		aram_req <= ~aram_req;
		aram_addr_sd <= ARAM_ADDR;
		aram_din <= ARAM_D;
	end

end

always @(posedge clk_mem) begin
/*
		bsram_rdD <= bsram_rd;
		bsram_wrD <= bsram_wr;
		if ((bsram_rd && BSRAM_ADDR[19:1] != bsram_sd_addr[19:1]) || (~bsram_wrD & bsram_wr) || (~bsram_rdD & bsram_rd)) begin
			bsram_req <= ~bsram_req;
			bsram_sd_addr <= BSRAM_ADDR;
			bsram_din <= BSRAM_D;
		end
*/

	vram0_weD <= VRAM0_WE;
	if (((~vram0_weD & VRAM0_WE) || (VRAM0_RD && VRAM0_ADDR[15:1] != vram0_addr_sd))) begin
		vram0_addr_sd <= VRAM0_ADDR[15:1];
		vram0_din <= VRAM0_D;
		vram0_req <= ~vram0_req;
	end

	vram1_weD <= VRAM1_WE;
	if (((~vram1_weD & VRAM1_WE) || (VRAM1_RD && VRAM1_ADDR[15:1] != vram1_addr_sd))) begin
		vram1_addr_sd <= VRAM1_ADDR[15:1];
		vram1_din <= VRAM1_D;
		vram1_req <= ~vram1_req;
	end

end

sdram sdram
(
	.*,
	.init_n(locked),
	.clk(clk_mem),
	.clkref(ce_vid),
	.sync_en(dcc==2'b10), // sync only in hires mode

	.rom_addr(rom_addr_sd),
	.rom_din(ioctl_dout),
	.rom_dout(rom_dout),
	.rom_req(rom_req),
	.rom_req_ack(rom_req_ack),
	.rom_we(cart_download),

	.wram_addr(wram_addr_sd),
	.wram_din(wram_din),
	.wram_dout(wram_dout),
	.wram_we(wram_wrD),
	.wram_req(wram_req),
	.wram_req_ack(wram_req_ack),

	.bsram_addr(bsram_sd_addr),
//	.bsram_din(bsram_din),
	.bsram_din(BSRAM_D),
	.bsram_dout(bsram_dout),
	.bsram_req(bsram_req),
	.bsram_req_ack(),
//	.bsram_we(~BSRAM_WE_N),
	.bsram_we(bsram_wrD),

	.bsram_io_addr(BSRAM_IO_ADDR),
	.bsram_io_din(BSRAM_IO_D),
	.bsram_io_dout(BSRAM_IO_Q),
	.bsram_io_req(bsram_io_req),
	.bsram_io_req_ack(),
	.bsram_io_we(bk_load),

	.vram0_req(vram0_req),
	.vram0_ack(),
	.vram0_addr(vram0_addr_sd),
	.vram0_din(vram0_din),
	.vram0_dout(VRAM0_Q),
	.vram0_we(vram0_weD),

	.vram1_req(vram1_req),
	.vram1_ack(),
	.vram1_addr(vram1_addr_sd),
	.vram1_din(vram1_din),
	.vram1_dout(VRAM1_Q),
	.vram1_we(vram1_weD),

	.aram_addr(aram_addr_sd),
	.aram_din(aram_din),
//	.aram_din(ARAM_D),
	.aram_dout(aram_dout),
	.aram_req(aram_req),
	.aram_req_ack(),
//	.aram_we(~ARAM_WE_N)
	.aram_we(aram_wr_last)
);

assign SDRAM_CKE = 1'b1;

// Populous cart detect
reg [1:0] populous;
always @(posedge clk_sys) begin
	reg old_download;

	old_download <= cart_download;

	if(~old_download && cart_download) begin
		populous <= 2'b11;
	end
	else if((ioctl_wr_last ^ ioctl_wr) & cart_download) begin
		if((ioctl_addr[23:4] == 'h212) || (ioctl_addr[23:4] == 'h1f2)) begin
			case(ioctl_addr[3:0])
				 6: if(ioctl_dout != 'h4F50) populous[ioctl_addr[13]] <= 0;
				 8: if(ioctl_dout != 'h5550) populous[ioctl_addr[13]] <= 0;
				10: if(ioctl_dout != 'h4F4C) populous[ioctl_addr[13]] <= 0;
				12: if(ioctl_dout != 'h5355) populous[ioctl_addr[13]] <= 0;
			endcase
		end
	end
end
////////////////////////////  SYSTEM  ///////////////////////////////////

wire cart_download   = ioctl_download & (ioctl_index[5:0] <= 6'h01);
wire cd_dat_download = ioctl_download & (ioctl_index[5:0] == 6'h02);

reg cd_en = 0;
always @(posedge clk_sys) begin
        if(img_mounted && img_size) cd_en <= 1;
        if(cart_download) cd_en <= 0;
end

wire [95:0] cd_comm;
wire        cd_comm_send;
reg  [15:0] cd_stat;
reg         cd_stat_rec;
reg         cd_dataout_req;
wire [79:0] cd_dataout;
wire        cd_dataout_send;
wire        cd_reset_req;

wire [21:0] cd_ram_a;
wire        cd_ram_rd, cd_ram_wr;
wire  [7:0] cd_ram_do;

wire        ce_rom;

wire signed [15:0] cdda_sl, cdda_sr, adpcm_s, psg_sl, psg_sr;

pce_top #(LITE) pce_top
(
	.RESET(reset),

	.CLK(clk_sys),

	.ROM_RD(ROM_RD),
	.ROM_RDY((rom_req == rom_req_ack) && (wram_req == wram_req_ack)),
	.ROM_A(ROM_ADDR),
	.ROM_DO(ROM_Q),
	.ROM_SZ(ioctl_addr[23:16]),
	.ROM_POP(populous[ioctl_addr[9]]),
	.ROM_CLKEN(ce_rom),

  .EXT_RAM_A(WRAM_ADDR),
	.EXT_RAM_DI(WRAM_Q),
	.EXT_RAM_DO(WRAM_D),
	.EXT_RAM_RD(),
	.EXT_RAM_CE(WRAM_CE),
	.EXT_RAM_WR(WRAM_WR),
	
	.ADRAM_A(ARAM_ADDR),
	.ADRAM_DI(ARAM_Q),
	.ADRAM_DO(ARAM_D),
	.ADRAM_WE(ARAM_WR),
	.ADRAM_RD(ARAM_RD),

	.BRM_A(bram_addr),
	.BRM_DO(bram_q),
	.BRM_DI(bram_data),
	.BRM_WE(bram_wr),

	.VRAM0_A(VRAM0_ADDR),
	.VRAM0_DO(VRAM0_D),
	.VRAM0_RD(VRAM0_RD),
	.VRAM0_WE(VRAM0_WE),
	.VRAM0_DI(VRAM0_Q),

	.VRAM1_A(VRAM1_ADDR),
	.VRAM1_DO(VRAM1_D),
	.VRAM1_RD(VRAM1_RD),
	.VRAM1_WE(VRAM1_WE),
	.VRAM1_DI(VRAM1_Q),

	.GG_EN(1'b0),
	.GG_CODE(),
	.GG_RESET(1'b0),
	.GG_AVAIL(1'b0),

	.SP64(1'b0),
	.SGX(sgx && !LITE),

	.JOY_OUT(joy_out),
	.JOY_IN(joy_in),

	.CD_EN(cd_en),
	.AC_EN(ac_en),
/*

        .CD_STAT(cd_stat[7:0]),
        .CD_MSG(cd_stat[15:8]),
        .CD_STAT_GET(cd_stat_rec),

        .CD_COMM(cd_comm),
        .CD_COMM_SEND(cd_comm_send),

        .CD_DOUT_REQ(cd_dataout_req),
        .CD_DOUT(cd_dataout),
        .CD_DOUT_SEND(cd_dataout_send),

        .CD_RESET(cd_reset_req),

        .CD_DATA(!cd_dat_byte ? cd_dat[7:0] : cd_dat[15:8]),
        .CD_WR(cd_wr),
        .CD_DATA_END(cd_dat_req),
        .CD_DM(cd_dm),
*/
	.CDDA_SL(cdda_sl),
	.CDDA_SR(cdda_sr),
	.ADPCM_S(adpcm_s),
	.PSG_SL(psg_sl),
	.PSG_SR(psg_sr),

	.BG_EN(1'b1),
	.SPR_EN(1'b1),
	.GRID_EN(1'b0),
	.CPU_PAUSE_EN(1'b0),

	.ReducedVBL(~overscan),
	.BORDER_EN(border),
	.VIDEO_DCC(dcc),
	.VIDEO_R(r),
	.VIDEO_G(g),
	.VIDEO_B(b),
	.VIDEO_BW(bw),
	.VIDEO_CE(ce_vid),
	//.VIDEO_CE_FS(ce_vid),
	.VIDEO_VS(vs),
	.VIDEO_HS(hs),
	.VIDEO_HBL(hbl),
	.VIDEO_VBL(vbl)
);

//////////////////   VIDEO   //////////////////
wire [2:0] r,g,b;
wire hs,vs;
wire hbl,vbl;
wire bw;
wire ce_vid;
wire [1:0] dcc;

mist_video #(.SD_HCNT_WIDTH(11), .COLOR_DEPTH(3)) mist_video
(
	.clk_sys(clk_sys),
	.scanlines(scanlines),
	.scandoubler_disable(scandoubler_disable),
	.ypbpr(ypbpr),
	.no_csync(no_csync),
	.rotate(2'b00),
	.ce_divider(1'b1),
	.SPI_DI(SPI_DI),
	.SPI_SCK(SPI_SCK),
	.SPI_SS3(SPI_SS3),
	.HSync(~hs),
	.VSync(~vs),
	.R(r),
	.G(g),
	.B(b),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B)
);

//////////////////   AUDIO   //////////////////
wire signed [16:0] audioL = psg_sl + cdda_sl + adpcm_s;
wire signed [16:0] audioR = psg_sr + cdda_sr + adpcm_s;

hybrid_pwm_sd_stereo dac
(
	.clk(clk_sys),
	.d_l({~audioL[16], audioL[15:1]}),
	.d_r({~audioR[16], audioR[15:1]}),
	.q_l(AUDIO_L),
	.q_r(AUDIO_R)
);


////////////////////////////  INPUT  ///////////////////////////////////
wire [31:0] joy_0 = joy_swap ? joy_b : joy_a;
wire [31:0] joy_1 = joy_swap ? joy_a : joy_b;

wire [15:0] joy_data;
always_comb begin
	case (joy_port)
		0: joy_data = mouse_en ? {mouse_data, mouse_data} : ~{4'hF, joy_0[11:8], joy_0[1], joy_0[2], joy_0[0], joy_0[3], joy_0[7:4]};
		1: joy_data = ~{4'hF, joy_1[11:8], joy_1[1], joy_1[2], joy_1[0], joy_1[3], joy_1[7:4]};
		2: joy_data = ~{4'hF, joy_2[11:8], joy_2[1], joy_2[2], joy_2[0], joy_2[3], joy_2[7:4]};
		3: joy_data = ~{4'hF, joy_3[11:8], joy_3[1], joy_3[2], joy_3[0], joy_3[3], joy_3[7:4]};
		4: joy_data = ~{4'hF, joy_4[11:8], joy_4[1], joy_4[2], joy_4[0], joy_4[3], joy_4[7:4]};
		default: joy_data = 16'h0FFF;
	endcase
end

wire [7:0] mouse_data;
assign mouse_data[3:0] = ~{joy_0[7:6], mouse_flags[0], mouse_flags[1]};

always_comb begin
	case (mouse_cnt)
		0: mouse_data[7:4] = ms_x[7:4];
		1: mouse_data[7:4] = ms_x[3:0];
		2: mouse_data[7:4] = ms_y[7:4];
		3: mouse_data[7:4] = ms_y[3:0];
	endcase
end

reg [3:0] joy_latch;
reg [2:0] joy_port;
reg [1:0] mouse_cnt;
reg [7:0] ms_x, ms_y;

always @(posedge clk_sys) begin : input_block
	reg  [1:0] last_gp;
	reg        high_buttons;
	reg [14:0] mouse_to;
	reg  [7:0] msr_x, msr_y;

	joy_latch <= joy_data[{high_buttons, joy_out[0], 2'b00} +:4];

	last_gp <= joy_out;

	if(joy_out[1]) mouse_to <= 0;
	else if(~&mouse_to) mouse_to <= mouse_to + 1'd1;

	if(&mouse_to) mouse_cnt <= 3;
	if(~last_gp[1] & joy_out[1]) begin
		mouse_cnt <= mouse_cnt + 1'd1;
		if(&mouse_cnt) begin
			ms_x  <= msr_x;
			ms_y  <= msr_y;
			msr_x <= 0;
			msr_y <= 0;
		end
	end

	if(mouse_strobe) begin
		msr_x <= 8'd0 - mouse_x[7:0];
		msr_y <= mouse_y[7:0];
	end

	if (joy_out[1]) begin
		joy_port  <= 0;
		joy_latch <= 0;
		if (~last_gp[1]) high_buttons <= ~high_buttons && buttons6;
	end
	else if (joy_out[0] && ~last_gp[0] && turbotap) begin
		joy_port <= joy_port + 3'd1;
	end
end

wire [1:0] joy_out;
wire [3:0] joy_in = joy_latch;

//////////////////////////// BACKUP RAM /////////////////////
reg  [19:1] BSRAM_IO_ADDR;
wire [15:0] BSRAM_IO_D;
wire [15:0] BSRAM_IO_Q;
reg  [15:0] bsram_io_q_save;
reg         bsram_io_req;
reg         bk_ena, bk_load;
reg         bk_state;
reg  [11:0] sav_size;

assign      sd_buff_din = sd_buff_addr[0] ? bsram_io_q_save[15:8] : bsram_io_q_save[7:0];

always @(posedge clk_sys) begin

	reg img_mountedD;
	reg ioctl_downloadD;
	reg bk_loadD, bk_saveD;
	reg sd_ackD;

	if (reset) begin
		bk_ena <= 0;
		bk_state <= 0;
		bk_load <= 0;
	end else begin
		img_mountedD <= img_mounted;
		if (~img_mountedD & img_mounted) begin
			if (|img_size) begin
				bk_ena <= 1;
				bk_load <= 1;
				sav_size <= img_size[20:9];
			end else begin
				bk_ena <= 0;
			end
		end

		ioctl_downloadD <= ioctl_download;
		if (~ioctl_downloadD & ioctl_download) bk_ena <= 0;

		bk_loadD <= bk_load;
		bk_saveD <= bk_save;
		sd_ackD  <= sd_ack;

		if (~sd_ackD & sd_ack) { sd_rd, sd_wr } <= 2'b00;

		case (bk_state)
		0:	if (bk_ena && ((~bk_loadD & bk_load) || (~bk_saveD & bk_save))) begin
				bk_state <= 1;
				sd_lba <= 0;
				sd_rd <= bk_load;
				sd_wr <= ~bk_load;
				if (bk_save) begin
					BSRAM_IO_ADDR <= 0;
					bsram_io_req <= ~bsram_io_req;
				end else
					BSRAM_IO_ADDR <= 19'h7ffff;
			end
		1:	if (sd_ackD & ~sd_ack) begin
				if (sd_lba[11:0] == sav_size) begin
					bk_load <= 0;
					bk_state <= 0;
				end else begin
					sd_lba <= sd_lba + 1'd1;
					sd_rd  <= bk_load;
					sd_wr  <= ~bk_load;
				end
			end
		endcase

		if (sd_buff_wr) begin
			if (sd_buff_addr[0]) begin
				BSRAM_IO_D[15:8] <= sd_buff_dout;
				bsram_io_req <= ~bsram_io_req;
				BSRAM_IO_ADDR <= BSRAM_IO_ADDR + 1'd1;
			end else
				BSRAM_IO_D[7:0] <= sd_buff_dout;
		end

		if (~sd_buff_addr[0]) bsram_io_q_save <= BSRAM_IO_Q;

		if (sd_buff_rd & sd_buff_addr[0]) begin
			bsram_io_req <= ~bsram_io_req;
			BSRAM_IO_ADDR <= BSRAM_IO_ADDR + 1'd1;
		end
	end
end

endmodule
