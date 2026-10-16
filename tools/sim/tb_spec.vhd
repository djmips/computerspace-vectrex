-- Spec-extraction testbench: runs computer_space_top with a scripted input
-- schedule and writes, per frame, only the lit pixels:
--   F <frame> <time_ms>
--   <x> <y> <v3v2v1v0>
-- x = game clocks since hsync rising edge, y = lines since vsync rising edge.
-- Frame 1 also gets one "B <y> <x_hblank_end> <x_hblank_start> <vblank>" row per line.
-- Input windows are generics in ms (an off time <= on time disables the input).

library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;

entity tb_spec is
	generic (
		DUMP_FILE  : string  := "spec.txt";
		FROM_MS    : integer := 1300;   -- start writing frames at this time
		END_MS     : integer := 6500;
		CW_ON      : integer := 1500;  CW_OFF   : integer := 3300;
		CCW_ON     : integer := 0;     CCW_OFF  : integer := 0;
		THR_ON     : integer := 3400;  THR_OFF  : integer := 3700;
		FIRE_ON    : integer := 3800;  FIRE_OFF : integer := 3850
	);
end tb_spec;

architecture sim of tb_spec is
	signal clock_50  : std_logic := '0';
	signal game_clk  : std_logic := '0';
	signal reset     : std_logic := '1';
	signal coin, start, cw, ccw, thr, fire : std_logic := '0';
	signal hsync, vsync, hblank, vblank : std_logic;
	signal video     : std_logic_vector(3 downto 0);
	signal done      : boolean := false;

	function win(t, a, b : integer) return std_logic is
	begin
		if b > a and t >= a and t < b then return '1'; else return '0'; end if;
	end function;
begin
	clock_50 <= not clock_50 after 10 ns when not done;
	game_clk <= not game_clk after 85.714 ns when not done;   -- 5.8333 MHz

	dut : entity work.computer_space_top
	port map (
		reset => reset, clock_50 => clock_50, game_clk => game_clk,
		signal_ccw => ccw, signal_cw => cw, signal_thrust => thr,
		signal_fire => fire, signal_start => start, signal_coin => coin,
		sw_2playpercoin => '0', sw_replay => '0',
		hsync => hsync, vsync => vsync, hblank => hblank, vblank => vblank,
		video => video, audio => open
	);

	stim : process
		variable t : integer := 0;   -- ms
	begin
		reset <= '1';
		wait for 1 us;
		reset <= '0';
		loop
			coin  <= win(t, 30, 130);
			start <= win(t, 180, 280);
			cw    <= win(t, CW_ON, CW_OFF);
			ccw   <= win(t, CCW_ON, CCW_OFF);
			thr   <= win(t, THR_ON, THR_OFF);
			fire  <= win(t, FIRE_ON, FIRE_OFF);
			wait for 1 ms;
			t := t + 1;
			if t >= END_MS then
				done <= true;
				wait;
			end if;
		end loop;
	end process;

	dump : process
		file f        : text open write_mode is DUMP_FILE;
		variable l    : line;
		variable x, y : integer := 0;
		variable hs_old, vs_old, hb_old : std_logic := '0';
		variable frame : integer := 0;
		variable hb_end, hb_start : integer := -1;
		variable rec  : boolean := false;
		function bit_of(s : std_logic) return character is
		begin
			if s = '1' then return '1'; else return '0'; end if;
		end function;
	begin
		wait until reset = '0';
		loop
			wait until rising_edge(game_clk);
			wait for 60 ns;   -- mid-period, as the DE1 top samples
			if vsync = '1' and vs_old = '0' then
				frame := frame + 1;
				y := 0;
				rec := (now / 1 ms) >= FROM_MS;
				if rec then
					write(l, string'("F ")); write(l, frame); write(l, ' ');
					write(l, integer(now / 1 ms)); writeline(f, l);
				end if;
			end if;
			if hsync = '1' and hs_old = '0' then
				if frame = 1 and not rec then
					null;
				end if;
				if frame = 3 then
					write(l, string'("B ")); write(l, y); write(l, ' ');
					write(l, hb_end); write(l, ' '); write(l, hb_start); write(l, ' ');
					write(l, bit_of(vblank)); writeline(f, l);
				end if;
				x := 0;
				y := y + 1;
				hb_end := -1; hb_start := -1;
			end if;
			if hblank = '0' and hb_old = '1' then hb_end := x; end if;
			if hblank = '1' and hb_old = '0' then hb_start := x; end if;
			if rec and (video(2) = '1' or video(1) = '1' or video(0) = '1' or video(3) = '1') then
				write(l, x); write(l, ' '); write(l, y); write(l, ' ');
				write(l, bit_of(video(3))); write(l, bit_of(video(2)));
				write(l, bit_of(video(1))); write(l, bit_of(video(0)));
				writeline(f, l);
			end if;
			hs_old := hsync; vs_old := vsync; hb_old := hblank;
			x := x + 1;
		end loop;
	end process;
end sim;
