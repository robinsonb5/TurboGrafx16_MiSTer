
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- -----------------------------------------------------------------------

entity chameleonv2_top is
	port (
-- Clocks
		clk50m : in std_logic;
		phi2_n : in std_logic;
		dotclk_n : in std_logic;

-- Buttons
		usart_cts : in std_logic;  -- Left button
		freeze_btn : in std_logic; -- Middle button
		reset_btn : in std_logic;  -- Right

-- PS/2, IEC, LEDs
		iec_present : in std_logic;

		ps2iec_sel : out std_logic;
		ps2iec : in unsigned(3 downto 0);

		ser_out_clk : out std_logic;
		ser_out_dat : out std_logic;
		ser_out_rclk : out std_logic;

		iec_clk_out : out std_logic;
		iec_srq_out : out std_logic;
		iec_atn_out : out std_logic;
		iec_dat_out : out std_logic;

-- SPI, Flash and SD-Card
		flash_cs : out std_logic;
		rtc_cs : out std_logic;
		mmc_cs : out std_logic;
		mmc_cd : in std_logic;
		mmc_wp : in std_logic;
		spi_clk : out std_logic;
		spi_miso : in std_logic;
		spi_mosi : out std_logic;

-- Clock port
		clock_ior : out std_logic;
		clock_iow : out std_logic;

-- C64 bus
		reset_in : in std_logic;

		ioef : in std_logic;
		romlh : in std_logic;

		dma_out : out std_logic;
		game_out : out std_logic;
		exrom_out : out std_logic;

		irq_in : in std_logic;
		irq_out : out std_logic;
		nmi_in : in std_logic;
		nmi_out : out std_logic;
		ba_in : in std_logic;
		rw_in : in std_logic;
		rw_out : out std_logic;

		sa_dir : out std_logic;
		sa_oe : out std_logic;
		sa15_out : out std_logic;
		low_a : inout unsigned(15 downto 0);

		sd_dir : out std_logic;
		sd_oe : out std_logic;
		low_d : inout unsigned(7 downto 0);

-- SDRAM
		ram_clk : out std_logic;
		ram_ldqm : out std_logic;
		ram_udqm : out std_logic;
		ram_ras : out std_logic;
		ram_cas : out std_logic;
		ram_we : out std_logic;
		ram_ba : out std_logic_vector(1 downto 0);
		ram_a : out std_logic_vector(12 downto 0);
		ram_d : inout std_logic_vector(15 downto 0);

-- IR eye
		ir_data : in std_logic;

-- USB micro
		usart_clk : in std_logic;
		usart_rts : in std_logic;
		usart_rx : out std_logic;
		usart_tx : in std_logic;

-- Video output
		red : out unsigned(4 downto 0);
		grn : out unsigned(4 downto 0);
		blu : out unsigned(4 downto 0);
		hsync_n : out std_logic;
		vsync_n : out std_logic;

-- Audio output
		sigma_l : out std_logic;
		sigma_r : out std_logic
	);
end entity;


architecture rtl of chameleonv2_top is
   constant reset_cycles : integer := 131071;
	
-- System clocks

	signal clk_sys : std_logic;
	signal clk_mem : std_logic;
	signal clk_85 : std_logic;
	signal pll_locked : std_logic;
	signal ena_1mhz : std_logic;
	signal ena_1khz : std_logic;
	signal phi2 : std_logic;
	
-- Global signals
	signal reset : std_logic;
	signal reset_n : std_logic;
	signal reset_core : std_logic;

-- LEDs
	signal led_green : std_logic;
	signal led_red : std_logic;

-- Docking station
	signal no_clock : std_logic;
	signal docking_station : std_logic;
	signal docking_irq : std_logic;
	signal phi_cnt : unsigned(7 downto 0);
	signal phi_end_1 : std_logic;
	
-- PS/2 Keyboard socket - used for second mouse
	signal ps2_keyboard_clk_in : std_logic;
	signal ps2_keyboard_dat_in : std_logic;
	signal ps2_keyboard_clk_out : std_logic;
	signal ps2_keyboard_dat_out : std_logic;

-- PS/2 Mouse
	signal ps2_mouse_clk_in: std_logic;
	signal ps2_mouse_dat_in: std_logic;
	signal ps2_mouse_clk_out: std_logic;
	signal ps2_mouse_dat_out: std_logic;
	
	signal sdram_req : std_logic := '0';
	signal sdram_ack : std_logic;
	signal sdram_we : std_logic := '0';
	signal sdram_a : unsigned(24 downto 0) := (others => '0');
	signal sdram_d : unsigned(7 downto 0);
	signal sdram_q : unsigned(7 downto 0);

	-- Video
	signal vga_red: std_logic_vector(7 downto 0);
	signal vga_green: std_logic_vector(7 downto 0);
	signal vga_blue: std_logic_vector(7 downto 0);
	signal vga_pixel : std_logic;
	signal vga_window : std_logic;
	signal vga_hsync : std_logic;
	signal vga_vsync : std_logic;
	signal vga_csync : std_logic;
	signal vga_selcsync : std_logic;
	
	signal red_dithered :unsigned(7 downto 0);
	signal grn_dithered :unsigned(7 downto 0);
	signal blu_dithered :unsigned(7 downto 0);
	signal hsync_n_dithered : std_logic;
	signal vsync_n_dithered : std_logic;
	
-- RS232 serial
	signal rs232_rxd : std_logic:='1';
	signal rs232_txd : std_logic;
	signal midi_rxd : std_logic;
	signal midi_txd : std_logic;

-- Sound
	signal audio_l : std_logic_vector(15 downto 0);
	signal audio_r : std_logic_vector(15 downto 0);

-- IO
	signal button_reset_n : std_logic;
	
	signal power_button : std_logic;
	signal play_button : std_logic;
	signal runstop : std_logic;
	signal c64_keys : unsigned(63 downto 0);
	signal c64_restore_key_n : std_logic;
	signal c64_nmi_n : std_logic;
	signal c64_joy1 : unsigned(6 downto 0);
	signal c64_joy2 : unsigned(6 downto 0);
	signal joystick3 : unsigned(6 downto 0);
	signal joystick4 : unsigned(6 downto 0);
	signal cdtv_joya : unsigned(5 downto 0);
	signal cdtv_joyb : unsigned(5 downto 0);
	signal joy1 : unsigned(7 downto 0);
	signal joy2 : unsigned(7 downto 0);
	signal joy3 : unsigned(7 downto 0);
	signal joy4 : unsigned(7 downto 0);
	signal ir : std_logic;
	signal ir_d : std_logic;

	signal amiga_reset_n : std_logic;
	signal amiga_key : unsigned(7 downto 0);
	signal amiga_key_stb : std_logic;

-- internal SPI signals
	
	signal spi_toguest : std_logic;
	signal spi_fromguest : std_logic;
	signal spi_ss2 : std_logic;
	signal spi_ss3 : std_logic;
	signal spi_ss4 : std_logic;
	signal conf_data0 : std_logic;
	signal spi_clk_int : std_logic;

	-- Declare guest component, since it's written in systemverilog
	
	COMPONENT turbografx16
		GENERIC (
			ypbpr_ena : integer := 0
		);
		PORT
		(
			clk_sys		:	 IN STD_LOGIC;
			clk_mem		:	 IN STD_LOGIC;
			RESET_N		:	 IN STD_LOGIC;
			VGA_R		:	 OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
			VGA_G		:	 OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
			VGA_B		:	 OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
			VGA_HS		:	 OUT STD_LOGIC;
			VGA_VS		:	 OUT STD_LOGIC;
			LED		:	 OUT STD_LOGIC;
			AUDIO_L		:	 OUT STD_LOGIC;
			AUDIO_R		:	 OUT STD_LOGIC;
			UART_RX		:	 IN STD_LOGIC := '1';
			SPI_SCK		:	 IN STD_LOGIC;
			SPI_DI		:	 IN STD_LOGIC;
			SPI_SD_DI		:	 IN STD_LOGIC;
			SPI_DO		:	 INOUT STD_LOGIC;
			SPI_SS2		:	 IN STD_LOGIC;
			SPI_SS3		:	 IN STD_LOGIC;
			SPI_SS4		:	 IN STD_LOGIC;
			CONF_DATA0		:	 IN STD_LOGIC;
			SDRAM_A		:	 OUT STD_LOGIC_VECTOR(12 DOWNTO 0);
			SDRAM_DQ		:	 INOUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			SDRAM_DQML		:	 OUT STD_LOGIC;
			SDRAM_DQMH		:	 OUT STD_LOGIC;
			SDRAM_nWE		:	 OUT STD_LOGIC;
			SDRAM_nCAS		:	 OUT STD_LOGIC;
			SDRAM_nRAS		:	 OUT STD_LOGIC;
			SDRAM_nCS		:	 OUT STD_LOGIC;
			SDRAM_BA		:	 OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
			SDRAM_CKE		:	 OUT STD_LOGIC
		);
	END COMPONENT;
	
begin

-- -----------------------------------------------------------------------
-- Unused pins
-- -----------------------------------------------------------------------
	iec_clk_out <= '0';
	iec_atn_out <= '0';
	iec_dat_out <= '0';
	iec_srq_out <= '0';
	nmi_out <= '0';
	usart_rx<='1';

	-- put these here?
	flash_cs <= '1';
	rtc_cs <= '0';
	
	clock_ior <='1';
	clock_iow <='1';
	irq_out <= not docking_irq;
	
-- -----------------------------------------------------------------------
-- Reset
-- -----------------------------------------------------------------------
	myReset : entity work.gen_reset
		generic map (
			resetCycles => reset_cycles
		)
		port map (
			clk => clk_85,
			enable => '1',

			button => not reset_btn,
			reset => reset,
			nreset => reset_n
		);

-- -----------------------------------------------------------------------
-- Clocks and PLL
-- -----------------------------------------------------------------------

	clocks: entity work.clocks
		port map
		(
			inclk0 => clk50m,
			c0 => ram_clk,
			c1 => clk_mem,
			c2 => clk_sys,
			c3 => clk_85,
			locked => pll_locked	
		);

-- -----------------------------------------------------------------------
-- 1 Mhz and 1 Khz clocks
-- -----------------------------------------------------------------------
	my1Mhz : entity work.chameleon_1mhz
		generic map (
			clk_ticks_per_usec => 100
		)
		port map (
			clk => clk_85,
			ena_1mhz => ena_1mhz,
			ena_1mhz_2 => open
		);

	my1Khz : entity work.chameleon_1khz
		port map (
			clk => clk_85,
			ena_1mhz => ena_1mhz,
			ena_1khz => ena_1khz
		);
	
-- -----------------------------------------------------------------------
-- PS2IEC multiplexer
-- -----------------------------------------------------------------------
	io_ps2iec_inst : entity work.chameleon2_io_ps2iec
		port map (
			clk => clk_85,

			ps2iec_sel => ps2iec_sel,
			ps2iec => ps2iec,

			ps2_mouse_clk => ps2_mouse_clk_in,
			ps2_mouse_dat => ps2_mouse_dat_in,
			ps2_keyboard_clk => ps2_keyboard_clk_in,
			ps2_keyboard_dat => ps2_keyboard_dat_in,

			iec_clk => open, -- iec_clk_in,
			iec_srq => open, -- iec_srq_in,
			iec_atn => open, -- iec_atn_in,
			iec_dat => open  -- iec_dat_in
		);

-- -----------------------------------------------------------------------
-- LED, PS2 and reset shiftregister
-- -----------------------------------------------------------------------
	io_shiftreg_inst : entity work.chameleon2_io_shiftreg
		port map (
			clk => clk_85,

			ser_out_clk => ser_out_clk,
			ser_out_dat => ser_out_dat,
			ser_out_rclk => ser_out_rclk,

			reset_c64 => reset,
			reset_iec => reset,
			ps2_mouse_clk => ps2_mouse_clk_out,
			ps2_mouse_dat => ps2_mouse_dat_out,
			ps2_keyboard_clk => ps2_keyboard_clk_out,
			ps2_keyboard_dat => ps2_keyboard_dat_out,
			led_green => led_green,
			led_red => led_red
		);

	cdtv : entity work.chameleon_cdtv_remote
	port map(
		clk => clk_85,
		ena_1mhz => ena_1mhz,
		ir => ir,
		key_power => power_button,
		key_play => play_button,
		joystick_a => cdtv_joya,
		joystick_b => cdtv_joyb
	);


-- -----------------------------------------------------------------------
-- Chameleon IO, docking station and cartridge port
-- -----------------------------------------------------------------------
	chameleon2_io_blk : block
	begin
		chameleon2_io_inst : entity work.chameleon2_io
			generic map (
				enable_docking_station => true,
				enable_cdtv_remote => false,
				enable_c64_joykeyb => true,
				enable_c64_4player => true
			)
			port map (
				clk => clk_85,
				ena_1mhz => ena_1mhz,
				phi2_n => phi2_n,
				dotclock_n => dotclk_n,

				reset => reset,

				ir_data => ir,
				ioef => ioef,
				romlh => romlh,

				dma_out => dma_out,
				game_out => game_out,
				exrom_out => exrom_out,

				ba_in => ba_in,
--				rw_in => rw_in,
				rw_out => rw_out,

				sa_dir => sa_dir,
				sa_oe => sa_oe,
				sa15_out => sa15_out,
				low_a => low_a,

				sd_dir => sd_dir,
				sd_oe => sd_oe,
				low_d => low_d,

				no_clock => no_clock,
				docking_station => docking_station,
				docking_irq => docking_irq,

				phi_cnt => phi_cnt,
				phi_end_1 => phi_end_1,

				joystick1 => c64_joy1,
				joystick2 => c64_joy2,
				joystick3 => joystick3,
				joystick4 => joystick4,
				keys => c64_keys,
--				restore_key_n => restore_n
				restore_key_n => open,
				amiga_power_led => led_green,
				amiga_drive_led => led_red,
				amiga_reset_n => amiga_reset_n,
				amiga_trigger => amiga_key_stb,
				amiga_scancode => amiga_key,
				midi_rxd => midi_rxd,
				midi_txd => midi_txd
			);
	end block;

-- Synchronise IR signal
process (clk_85)
begin
	if rising_edge(clk_85) then
		ir_d<=ir_data;
		ir<=ir_d;
	end if;
end process;


--joy1<=not gp1_run & not gp1_select & (c64_joy1 and cdtv_joy1);
--runstop<='0' when c64_keys(63)='0' and c64_joy1="1111111" else '1';
-- gp1_run<=c64_keys(11) and c64_keys(56) when c64_joy1="111111" else '1';
-- gp1_select<=c64_keys(60) when c64_joy1="111111" else '1';
joy1<='1' & c64_joy1(6) & (c64_joy1(5 downto 0) and cdtv_joya);
joy2<="1" & c64_joy2(6) & (c64_joy2(5 downto 0) and cdtv_joyb);
joy3<="1" & joystick3;
joy4<="1" & joystick4;
	
	-- Guest core
	
	midi_txd<='1';
	
	guest: COMPONENT turbografx16
		generic map
		(
			ypbpr_ena => 0
		)
		PORT map
		(
			-- clocks and reset
			clk_sys => clk_sys,
			clk_mem => clk_mem,
			RESET_N => reset_core,
			
			-- SDRAM
			SDRAM_DQ => ram_d,
			SDRAM_A => ram_a,
			SDRAM_DQML => ram_ldqm,
			SDRAM_DQMH => ram_udqm,
			SDRAM_nWE => ram_we,
			SDRAM_nCAS => ram_cas,
			SDRAM_nRAS => ram_ras,
--			SDRAM_nCS => ram_cs_n,	-- Hardwired on TC64
			SDRAM_BA => ram_ba,
--			SDRAM_CKE => ram_cke, -- Hardwired on TC64

			-- SPI interface to control module
			SPI_SD_DI => spi_miso,
			SPI_DO => spi_fromguest,
			SPI_DI => spi_toguest,
			SPI_SCK => spi_clk_int,
			SPI_SS2	=> spi_ss2,
			SPI_SS3 => spi_ss3,
			SPI_SS4	=> spi_ss4,			
			CONF_DATA0 => conf_data0,
			-- Video output
			VGA_HS => vga_hsync,
			VGA_VS => vga_vsync,
			VGA_R => vga_red(7 downto 2),
			VGA_G => vga_green(7 downto 2),
			VGA_B => vga_blue(7 downto 2),
			-- Audio output
			AUDIO_L => sigma_l,
			AUDIO_R => sigma_r
	);
	
	
	-- Register video outputs, invert sync for Chameleon V1 hardware
	
	process(clk_sys)
	begin
		if rising_edge(clk_sys) then
			red<=unsigned(vga_red(7 downto 3));
			grn<=unsigned(vga_green(7 downto 3));
			blu<=unsigned(vga_blue(7 downto 3));
			hsync_n<=vga_hsync;
			vsync_n<=vga_vsync;
		end if;
	end process;


	-- Control module
	
	controller : entity work.controller
		generic map (
			sysclk_frequency => 420,
			debug => false
		)
		port map (
			clk => clk_sys,
			reset_in => reset_n,
			reset_out => reset_core,

			-- SPI signals
			spi_miso => spi_miso,
			spi_mosi	=> spi_mosi,
			spi_clk => spi_clk_int,
			spi_cs => mmc_cs,
			spi_fromguest => spi_fromguest,
			spi_toguest => spi_toguest,
			spi_ss2 => spi_ss2,
			spi_ss3 => spi_ss3,
			spi_ss4 => spi_ss4,
			conf_data0 => conf_data0,
			spi_ack => '1', -- SPI data is direct on TC64V2
			
			-- PS/2 signals
			ps2k_clk_in => ps2_keyboard_clk_in,
			ps2k_dat_in => ps2_keyboard_dat_in,
			ps2k_clk_out => ps2_keyboard_clk_out,
			ps2k_dat_out => ps2_keyboard_dat_out,
			ps2m_clk_in => ps2_mouse_clk_in,
			ps2m_dat_in => ps2_mouse_dat_in,
			ps2m_clk_out => ps2_mouse_clk_out,
			ps2m_dat_out => ps2_mouse_dat_out,

			-- UART
			rxd => rs232_rxd,
			txd => rs232_txd
	);
	
	spi_clk <= spi_clk_int;
	
end architecture;

