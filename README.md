# Computer Space for the Vectrex

A port of Nutting Associates' *Computer Space* (1971) to the Vectrex, in 6809 assembly.

The game rules, timings and artwork come from the gate-level FPGA recreation of the original boards
(Mattias G 2015, DarFPGA 2017), studied in the companion repo
[djmips/computerspace](https://github.com/djmips/computerspace), which runs that core on a Terasic DE1.

## Status

Toolchain skeleton: the cartridge boots through the BIOS title ("COMPUTER SPACE") and draws a
placeholder shape.

## Building

Uses VIDE's own assembler (Asmj) through a vecx-run kit, which bundles it with a build script: set
`VECX_KIT` to the kit's folder. Java 11 or newer.

```
powershell -ExecutionPolicy Bypass -File build.ps1
```

Output: `build\computerspace.bin`, a standard single-bank cartridge of at most 32K, and
`build\computerspace.cnt` (VIDE symbols). The project also opens in the VIDE IDE
(`ComputerSpaceProjectProperty.xml`).

## Running

- **Emulator (headless, with screenshots):**
  `vecx-run.exe --headless --bios skip --seconds 3 --png-at 2.5 build\computerspace.bin`
- **Hardware:** copy `build\computerspace.bin` to a VEXTREME or UVMC2 multicart.

## Notes

- After `Reset0Ref` the integrators stay held at zero (VIA PCR `$CC`) until a `Moveto`; `Draw_VLc`
  does not release them, so a list drawn straight after `Reset0Ref` collapses to a dot. Move first
  (`ldd #0` / `jsr Moveto_d`).
- `VECTREX.I` is the Vectrex BIOS include (Bruce Tomlin, changed by Malban).
