#!/bin/sh
# Build the core (with the real sound module) and tb_spec; extra args go to the simulator.
set -e
cd "$(dirname "$0")"
G=/e/tools/ghdl/bin/ghdl.exe
O="--std=93c -fsynopsys -fexplicit -frelaxed --workdir=build"
rm -rf build && mkdir -p out && python -I prep_rtl.py >/dev/null
for f in v74161 v74161_16bit scan_counter saucer_diode_image rocket_diode_images \
         sync_star_board motion_board memory_board clocks computer_space_sound computer_space_logic computer_space_top; do
	$G -a $O build/src/$f.vhd
done
$G -a $O tb_spec.vhd
$G -e $O tb_spec
$G -r $O tb_spec --ieee-asserts=disable "$@"
