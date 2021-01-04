-- -----------------------------------------------------------------------
--
-- Turbo Chameleon
--
-- Toplevel file for Turbo Chameleon 64
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;

library work;

-- -----------------------------------------------------------------------

entity chameleon_toplevel is
	generic (
		resetCycles: integer := 131071
	);
	port (
-- Clocks
		clk8 : in std_logic;
		phi2_n : in std_logic;
		dotclock_n : in std_logic;

-- Bus
		romlh_n : in std_logic;
		ioef_n : in std_logic;

-- Buttons
		freeze_n : in std_logic;

-- MMC/SPI
		spi_miso : in std_logic;
		mmc_cd_n : in std_logic;
		mmc_wp : in std_logic;

-- MUX CPLD
		mux_clk : out std_logic;
		mux : out unsigned(3 downto 0);
		mux_d : out unsigned(3 downto 0);
		mux_q : in unsigned(3 downto 0);

-- USART
		usart_tx : in std_logic;
		usart_clk : in std_logic;
		usart_rts : in std_logic;
		usart_cts : in std_logic;

-- SDRam
		sd_clk : out std_logic;
		sd_data : inout std_logic_vector(15 downto 0);
		sd_addr : out std_logic_vector(12 downto 0);
		sd_we_n : out std_logic;
		sd_ras_n : out std_logic;
		sd_cas_n : out std_logic;
		sd_ba_0 : out std_logic;
		sd_ba_1 : out std_logic;
		sd_ldqm : out std_logic;
		sd_udqm : out std_logic;

-- Video
		red : out unsigned(4 downto 0);
		grn : out unsigned(4 downto 0);
		blu : out unsigned(4 downto 0);
		nHSync : out std_logic;
		nVSync : out std_logic;

-- Audio
		sigmaL : out std_logic;
		sigmaR : out std_logic
	);
end entity;

-- -----------------------------------------------------------------------

architecture rtl of chameleon_toplevel is
   constant reset_cycles : integer := 131071;
	
-- System clocks
	signal clk_sys : std_logic;
	signal clk_mem : std_logic;
	signal clk_85 : std_logic;
	signal reset_button_n : std_logic;
	signal pll_locked : std_logic;
	
-- Global signals
	signal reset_8 : std_logic;
	signal reset_28 : std_logic;
	signal reset : std_logic;
	signal reset_n : std_logic;
	signal reset_core : std_logic;
	
-- MUX
	signal mux_clk_reg : std_logic := '0';
	signal mux_reg : unsigned(3 downto 0) := (others => '1');
	signal mux_d_reg : unsigned(3 downto 0) := (others => '1');
	signal mux_d_regd : unsigned(3 downto 0) := (others => '1');
	signal mux_regd : unsigned(3 downto 0) := (others => '1');

-- LEDs
	signal led_green : std_logic;
	signal led_red : std_logic;
	signal socleds : std_logic_vector(7 downto 0);

-- PS/2 Keyboard
	signal ps2_keyboard_clk_in : std_logic;
	signal ps2_keyboard_dat_in : std_logic;
	signal ps2_keyboard_clk_out : std_logic;
	signal ps2_keyboard_dat_out : std_logic;

-- PS/2 Mouse
	signal ps2_mouse_clk_in: std_logic;
	signal ps2_mouse_dat_in: std_logic;
	signal ps2_mouse_clk_out: std_logic;
	signal ps2_mouse_dat_out: std_logic;

-- SD card
	signal spi_mosi : std_logic;
	signal spi_cs : std_logic;
	signal spi_clk : std_logic;
	signal spi_raw_ack : std_logic;
	signal spi_raw_ack_d : std_logic;
	signal spi_ack : std_logic;

-- internal SPI signals
	
	signal spi_toguest : std_logic;
	signal spi_fromguest : std_logic;
	signal spi_ss2 : std_logic;
	signal spi_ss3 : std_logic;
	signal spi_ss4 : std_logic;
	signal conf_data0 : std_logic;
	signal spi_clk_int : std_logic;
	
-- RTC

	signal rtc_cs : std_logic;
	
-- RS232 serial
	signal rs232_rxd : std_logic;
	signal rs232_txd : std_logic;
	signal midi_rxd : std_logic;
	signal midi_txd : std_logic;

-- IO
	signal ena_1mhz : std_logic;
	signal button_reset_n : std_logic;

	signal power_button : std_logic;
	signal play_button : std_logic;

	signal no_clock : std_logic;
	signal docking_station : std_logic;
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
	signal usart_rx : std_logic:='1'; -- Safe default
	signal ir : std_logic;
	
	signal amiga_reset_n : std_logic;
	signal amiga_key : unsigned(7 downto 0);
	signal amiga_key_stb : std_logic;

	signal vga_csync : std_logic;
	signal vga_hsync : std_logic;
	signal vga_vsync : std_logic;
	signal vga_red : std_logic_vector(7 downto 0);
	signal vga_green : std_logic_vector(7 downto 0);
	signal vga_blue : std_logic_vector(7 downto 0);
	
	signal red_dithered :unsigned(7 downto 0);
	signal grn_dithered :unsigned(7 downto 0);
	signal blu_dithered :unsigned(7 downto 0);
	signal hsync_n_dithered : std_logic;
	signal vsync_n_dithered : std_logic;

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
-- Clocks and PLL
-- -----------------------------------------------------------------------

	clocks: entity work.clocks
		port map
		(
			inclk0 => clk8,
			c0 => sd_clk,
			c1 => clk_mem,
			c2 => clk_sys,
			c3 => clk_85,
			locked => pll_locked	
		);

	my1mhz : entity work.chameleon_1mhz
		generic map (
			-- Timer calibration. Clock speed in Mhz.
			clk_ticks_per_usec => 85
		)
		port map(
			clk => clk_85,
			ena_1mhz => ena_1mhz
		);

	-- Reset handling
		
	myReset : entity work.gen_reset
		generic map (
			resetCycles => reset_cycles
		)
		port map (
			clk => clk8,
			enable => '1',
			button => not (pll_locked and button_reset_n),
			reset => reset_8
		);
		
	process(clk_sys,reset_8)
	begin
		if rising_edge(clk_sys) then
			reset_28<=reset_8;
			reset<=reset_28;
		end if;
	end process;
	
	reset_n<= not reset;

	-- IO handling
	
	myIO : entity work.chameleon_io
		generic map (
			enable_docking_station => true,
			enable_docking_irq => true,
			enable_c64_joykeyb => true,
			enable_c64_4player => true,
			enable_raw_spi => true,
			enable_iec_access =>true
		)
		port map (
		-- Clocks
			clk => clk_85,
			clk_mux => clk_85,
			ena_1mhz => ena_1mhz,
			reset => reset,
			
			no_clock => no_clock,
			docking_station => docking_station,
			
		-- Chameleon FPGA pins
			-- C64 Clocks
			phi2_n => phi2_n,
			dotclock_n => dotclock_n, 
			-- C64 cartridge control lines
			io_ef_n => ioef_n,
			rom_lh_n => romlh_n,
			-- SPI bus
			spi_miso => spi_miso,
			-- CPLD multiplexer
			mux_clk => mux_clk,
			mux => mux,
			mux_d => mux_d,
			mux_q => mux_q,
			
			to_usb_rx => usart_rx,

		-- SPI raw signals (enable_raw_spi must be set to true)
			rtc_cs => rtc_cs,
			mmc_cs_n => spi_cs,
			spi_raw_clk => spi_clk,
			spi_raw_mosi => spi_mosi,
			spi_raw_ack => spi_raw_ack,

		-- LEDs
			led_green => led_green,
			led_red => led_red,
			ir => ir,
		
		-- PS/2 Keyboard
			ps2_keyboard_clk_out => ps2_keyboard_clk_out,
			ps2_keyboard_dat_out => ps2_keyboard_dat_out,
			ps2_keyboard_clk_in => ps2_keyboard_clk_in,
			ps2_keyboard_dat_in => ps2_keyboard_dat_in,
	
		-- PS/2 Mouse
			ps2_mouse_clk_out => ps2_mouse_clk_out,
			ps2_mouse_dat_out => ps2_mouse_dat_out,
			ps2_mouse_clk_in => ps2_mouse_clk_in,
			ps2_mouse_dat_in => ps2_mouse_dat_in,

		-- Buttons
			button_reset_n => button_reset_n,

		-- Joysticks
			joystick1 => c64_joy1,
			joystick2 => c64_joy2,
			joystick3 => joystick3, 
			joystick4 => joystick4,

		-- Keyboards
			keys => c64_keys,
			restore_key_n => c64_restore_key_n,
			c64_nmi_n => c64_nmi_n,

			amiga_reset_n => amiga_reset_n,
			amiga_trigger => amiga_key_stb,
			amiga_scancode => amiga_key,

			midi_txd => midi_txd,
			midi_rxd => midi_rxd,

			iec_atn_out => rs232_txd,
			iec_clk_in => rs232_rxd
--			iec_clk_out : in std_logic := '1';
--			iec_dat_out : in std_logic := '1';
--			iec_srq_out : in std_logic := '1';
--			iec_dat_in : out std_logic;
--			iec_atn_in : out std_logic;
--			iec_srq_in : out std_logic
	
		);

	-- Widen the SPI ack pulse		
	process(clk_85,spi_raw_ack,spi_raw_ack_d)
	begin
		if rising_edge(clk_85) then
			spi_raw_ack_d <= spi_raw_ack;
		end if;
		spi_ack <= spi_raw_ack or spi_raw_ack_d;
	end process;

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

	rtc_cs<='0';
			
	runstop<='0' when c64_keys(63)='0' and c64_joy1="1111111" else '1';
	joy1<="1" & c64_joy1(6) & (c64_joy1(5 downto 0) and cdtv_joya);
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
			SDRAM_DQ => sd_data,
			SDRAM_A => sd_addr,
			SDRAM_DQML => sd_ldqm,
			SDRAM_DQMH => sd_udqm,
			SDRAM_nWE => sd_we_n,
			SDRAM_nCAS => sd_cas_n,
			SDRAM_nRAS => sd_ras_n,
--			SDRAM_nCS => sd_cs_n,	-- Hardwired on TC64
			SDRAM_BA(0) => sd_ba_0,
			SDRAM_BA(1) => sd_ba_1,
--			SDRAM_CKE => sd_cke, -- Hardwired on TC64

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
			AUDIO_L => sigmaL,
			AUDIO_R => sigmaR
	);
	
	
	-- Register video outputs, invert sync for Chameleon V1 hardware
	
	process(clk_sys)
	begin
		if rising_edge(clk_sys) then
			red<=unsigned(vga_red(7 downto 3));
			grn<=unsigned(vga_green(7 downto 3));
			blu<=unsigned(vga_blue(7 downto 3));
			nHSync<=not vga_hsync;
			nVSync<=not vga_vsync;
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
			spi_cs => spi_cs,
			spi_fromguest => spi_fromguest,
			spi_toguest => spi_toguest,
			spi_ss2 => spi_ss2,
			spi_ss3 => spi_ss3,
			spi_ss4 => spi_ss4,
			conf_data0 => conf_data0,
			spi_ack => spi_ack,
			
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
