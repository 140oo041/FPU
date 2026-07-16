![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# FPU-130

FPU-130 is a floating-point coprocessor built around a compact, iterative `bfloat16` datapath. A host talks to it over SPI to issue commands and send operands, can stream operands faster through a parallel burst path, and gets back a `bfloat16` result along with status flags. The design is being developed toward tapeout on the SkyWater 130nm (Sky130) shuttle through Tiny Tapeout.

The full design spec is published at [140oo041.github.io/FPU](https://140oo041.github.io/FPU/); the source lives in [docs/FPU_Design_Spec_v0.4_1.html](docs/FPU_Design_Spec_v0.4_1.html). This repository also holds the project scaffolding and early RTL/testbench work — see [Project Status](#project-status) below for where things stand.

## Design Summary

- Number format: `bfloat16` (`1` sign bit, `8` exponent bits, `7` mantissa bits)
- Core clock: `40 MHz`
- SPI clock: up to `10 MHz`, Mode 0, MSB-first
- Transport modes:
  - SPI command/data path
  - Parallel burst operand path using valid/ready handshakes
- Execution model: iterative datapath that reuses a shared add/sub core to reduce area
- Integrity: instruction `CRC-3/GSM`, payload `CRC-8/SMBUS`
- State: one 16-bit accumulator (`ACC`) for chained operations

## Supported Operations

| Opcode | Mnemonic | Description |
| --- | --- | --- |
| `000` | `ADD` | `a + b` |
| `001` | `SUB` | `a - b` |
| `010` | `MUL` | `a * b` |
| `011` | `DIV` | `a / b` |
| `100` | `NEG` | `-a` |
| `101` | `ABS` | `abs(a)` |
| `110` | `SLT` | returns `1.0` if `a < b`, else `0.0` |
| `111` | `NOP` | no writeback, used for status/control flow |

Latency varies by operation: the spec budgets roughly `3-4` cycles for add/sub, `6-8` for multiply, and `6-10` for divide. Because timing isn't fixed, the host needs to either poll `BUSY` or wait on the burst-side output handshake rather than assuming a result is ready after a set number of cycles.

## Number Format

All operands and results use `bfloat16`. Each value is transferred as two bytes, high byte first:

- `bit 15`: sign
- `bits 14:7`: exponent with bias `127`
- `bits 6:0`: mantissa

Because the exponent is compatible with IEEE-754 `fp32`, a host can usually get away with just truncating an `fp32` value down to its top 16 bits to produce a `bfloat16`.

## Interface

### Tiny Tapeout Pin Map

| Pin | Direction | Signal | Purpose |
| --- | --- | --- | --- |
| `ui_in[7:0]` | in | `byte_in` | parallel burst operand byte |
| `uo_out[7:0]` | out | `byte_out` | result/status byte output |
| `uio[0]` | in | `spi_cs_n` | SPI chip select |
| `uio[1]` | in | `spi_mosi` | SPI host-to-FPU data |
| `uio[2]` | out | `spi_miso` | SPI FPU-to-host data |
| `uio[3]` | in | `spi_sck` | SPI clock |
| `uio[4]` | in | `in_valid` | burst input valid |
| `uio[5]` | out | `in_ready` | burst input ready |
| `uio[6]` | out | `out_valid` | burst output valid |
| `uio[7]` | in | `out_ready` | burst output ready |

The design spec proposes a constant `uio_oe = 0x64`, which makes `uio[2]`, `uio[5]`, and `uio[6]` outputs.

### SPI Framing

Each transaction starts with an 8-bit instruction byte:

- `bit 7`: `burst`
- `bit 6`: `acc`
- `bits 5:3`: opcode
- `bits 2:0`: instruction `CRC-3`

That is followed by a CRC-protected payload:

1. control byte
2. operand bytes (`bfloat16`, high byte first)
3. trailing payload `CRC-8`

If `acc = 1`, the first operand comes from the internal accumulator and the host only sends the remaining operand.

### Control and Status Bytes

The host sends a control byte with:

- `TAG[1:0]`: request tag echoed back in status
- `SAT`: saturate on overflow instead of producing infinity
- `CLRF`: clear sticky flags
- `CLRA`: clear accumulator
- `RND[1:0]`: rounding mode

The FPU returns a status byte with:

- `BUSY`
- `NAN`
- `OVF`
- `UNF`
- `INX`
- `ERR`
- echoed `TAG[1:0]`

## Burst Mode

When `burst = 1`, the instruction byte still arrives over SPI, but the operand payload moves over the dedicated `ui_in[7:0]` bus instead, using `in_valid`/`in_ready` handshaking. Results come back the same way, on `uo_out[7:0]` with `out_valid`/`out_ready`.

This mode is built for streaming workloads — particularly accumulate chains, where the host repeatedly feeds in one new operand at a time while the FPU reuses `ACC` as the other.

## Microarchitecture

The design is intentionally area-driven rather than throughput-driven:

- shared add/sub significand core
- exponent align/add/subtract logic
- normalize and round stage
- iterative multiply/divide sequencer
- 16-bit `ACC` register for chaining results
- transport handlers for SPI and burst I/O

The spec's first-order estimate puts the full design at roughly `1110` gate equivalents before place-and-route overhead — big enough that it recommends budgeting for a `2x2` Tiny Tapeout footprint rather than a single tile.

## Repository Layout

- [docs/FPU_Design_Spec_v0.4_1.html](docs/FPU_Design_Spec_v0.4_1.html): full design spec
- [docs/index.html](docs/index.html): GitHub Pages entry page for the spec
- [docs/info.md](docs/info.md): Tiny Tapeout datasheet source
- [src/project.v](src/project.v): current RTL work-in-progress
- [src/config.json](src/config.json): project configuration
- [test/test.py](test/test.py): cocotb tests
- [test/Makefile](test/Makefile): simulation entrypoint

## Running the Tests

Install the Python dependencies:

```sh
python -m pip install -r test/requirements.txt
```

Run the RTL simulation:

```sh
cd test
make -B
```

If you want to inspect waveforms:

```sh
gtkwave tb.fst tb.gtkw
```

## Project Status

The spec is well ahead of the RTL at this point. A few things to keep in mind:

- the top-level source in [src/project.v](src/project.v) is still an early scaffold
- `info.yaml` and [docs/info.md](docs/info.md) are still template content
- the existing tests focus mainly on the current SPI receive path, not the full arithmetic datapath defined in the spec

In short, treat this repo as a design specification plus early implementation work in progress — not yet a finished Tiny Tapeout submission.
