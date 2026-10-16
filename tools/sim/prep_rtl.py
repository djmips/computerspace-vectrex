"""Copy ../rtl into build/src with the small patches GHDL needs.

rtl/ stays exactly as upstream (Quartus accepts it). GHDL rejects:
  * sync_star_board: `slv = "0101"` is ambiguous with both
    std_logic_1164 and std_logic_unsigned visible -> compare integers.
  * motion_board: a single-element association `Q(11) => x` on an out port
    -> add `open` for the remaining bits.
"""
import os
import pathlib
import re
import sys

here = pathlib.Path(__file__).resolve().parent
src = pathlib.Path(os.environ.get("CS_RTL", pathlib.Path(__file__).resolve().parents[3] / "computerspace" / "rtl"))
dst = here / "build" / "src"
dst.mkdir(parents=True, exist_ok=True)

for f in src.glob("*.vhd"):
    text = f.read_text(encoding="latin-1")
    if f.name == "sync_star_board.vhd":
        text, n = re.subn(r'when g3_in = "([01]{4})"',
                          lambda m: f"when conv_integer(g3_in) = {int(m.group(1), 2)}",
                          text)
        assert n >= 10, n
    if f.name == "motion_board.vhd":
        for bit in (11, 9):
            old = f"Q({bit}) => "
            assert old in text
            text = re.sub(rf"Q\({bit}\) => (\w+)",
                          rf"Q(15 downto {bit + 1}) => open, Q({bit}) => \1, Q({bit - 1} downto 0) => open",
                          text)
    if f.name == "motion_board.vhd":
        # Scratch-only: the rocket missile timer as Quartus builds it (count while active,
        # clear after the lifetime), so the simulated missile expires as on the board.
        i = text.index("elsif (rising_edge(timer_base_clk) and missile_timer = '1') then")
        j = text.index("end if;", text.index("MB_2_rocket <= '0';", i))
        text = text[:i] + """elsif rising_edge(timer_base_clk) then
	if missile_timer = '1' then
		missile_life_time_counter <= missile_life_time_counter + 1;
	elsif missile_life_time_counter > rocket_missile_life_time_duration then
		missile_life_time_counter <= 0;
	end if;
	if missile_life_time_counter > rocket_missile_life_time_duration then
		missile_timer <= '0';
		d6_1 <= '1';
		MB_2_rocket <= '0';
	end if;
""" + text[j:]
    (dst / f.name).write_text(text, encoding="latin-1")

print("prepared", dst)
