-- Multiplier-based RGB -> YPbPr conversion

-- Copyright 2020 by Alastair M. Robinson

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;


entity RGBtoYPbPr is
port
(
	clk : in std_logic;
	ena : in std_logic;

	red_in : in std_logic_vector(7 downto 0);
	green_in : in std_logic_vector(7 downto 0);
	blue_in : in std_logic_vector(7 downto 0);
	hs_in : in std_logic;
	vs_in : in std_logic;
	cs_in : in std_logic;
	pixel_in : in std_logic;
	
	red_out : out std_logic_vector(7 downto 0);
	green_out : out std_logic_vector(7 downto 0);
	blue_out : out std_logic_vector(7 downto 0);
	hs_out : out std_logic;
	vs_out : out std_logic;
	cs_out : out std_logic;
	pixel_out : out std_logic
);
end entity;

architecture behavioural of RGBtoYPbPr is

signal r_y : unsigned(15 downto 0);
signal g_y : unsigned(15 downto 0);
signal b_y : unsigned(15 downto 0);

signal r_b : unsigned(15 downto 0);
signal g_b : unsigned(15 downto 0);
signal b_b : unsigned(15 downto 0);

signal r_r : unsigned(15 downto 0);
signal g_r : unsigned(15 downto 0);
signal b_r : unsigned(15 downto 0);

signal y : unsigned(15 downto 0);
signal b : unsigned(15 downto 0);
signal r : unsigned(15 downto 0);

signal hs_d : std_logic;
signal vs_d : std_logic;
signal cs_d : std_logic;
signal pixel_d : std_logic;

begin

	red_out <= std_logic_vector(r(15 downto 8));
	green_out <= std_logic_vector(y(15 downto 8));
	blue_out <= std_logic_vector(b(15 downto 8));
	
	-- Multiply in the first stage...

	process(clk)
	begin

		if rising_edge(clk) then
		
			hs_d <= hs_in;		-- Register sync, pixel clock, etc
			vs_d <= vs_in;		-- so they're delayed the same amount as the incoming video
			cs_d <= cs_in;
			pixel_d <= pixel_in;
		
			if ena='1' then
				-- (Y  =  0.299*R + 0.587*G + 0.114*B)
				r_y <= unsigned(red_in) * 76;
				g_y <= unsigned(green_in) * 150;
				b_y <= unsigned(blue_in) * 29;
		
				-- (Pb = -0.169*R - 0.331*G + 0.500*B)
				r_b <= unsigned(red_in) * 43;
				g_b <= unsigned(green_in) * 84;
				b_b <= unsigned(blue_in) * 128;

				-- (Pr =  0.500*R - 0.419*G - 0.081*B)
				r_r <= unsigned(red_in) * 128;
				g_r <= unsigned(green_in) * 107;
				b_r <= unsigned(blue_in) * 20;
			else
				r_r(15 downto 8) <= unsigned(red_in);	-- Passthrough
				g_y(15 downto 8) <= unsigned(green_in);
				b_b(15 downto 8) <= unsigned(blue_in);
			end if;
		end if;

	end process;

	-- Second stage - adding
	
	process(clk)
	begin

		if rising_edge(clk) then
		
			hs_out <= hs_d;
			vs_out <= vs_d;
			cs_out <= cs_d;
			pixel_out <= pixel_d;
		
			if ena='1' then
				y <= r_y + g_y + b_y;
				b <= 32768 + b_b - r_b - g_b;
				r <= 32768 + r_r - g_r - b_r;	
			else
				y <= g_y;	-- Passthrough
				b <= b_b;
				r <= r_r;
			end if;
		end if;
		
	end process;
	
end architecture;
