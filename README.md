![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# FPU-130

FPU-130 is a Tiny Tapeout floating-point coprocessor designed around a compact, iterative `bfloat16` datapath. It accepts commands and operands from a host over SPI, supports a higher-throughput parallel burst path for operand streaming, and returns a `bfloat16` result together with status flags.

The full design specification lives in [docs/FPU_Design_Spec_v0.4_1.html](docs/FPU_Design_Spec_v0.4_1.html). This repository currently contains that spec, project scaffolding, and early RTL/testbench work.

If you want to publish the spec with GitHub Pages, this repo now includes [docs/index.html](docs/index.html) as a Pages landing page for the design spec. In the repository settings, set Pages to deploy from the `main` branch and the `/docs` folder.

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

Latency is variable by operation. The spec budgets roughly `3-4` cycles for add/sub, `6-8` for multiply, and `6-10` for divide, which is why the host must poll `BUSY` or use the burst-side output handshake instead of assuming fixed timing.

## Number Format

All operands and results use `bfloat16`. Each value is transferred as two bytes, high byte first:

- `bit 15`: sign
- `bits 14:7`: exponent with bias `127`
- `bits 6:0`: mantissa

This keeps the exponent compatible with IEEE-754 `fp32`, so a host can usually generate `bfloat16` values by truncating the top 16 bits of an `fp32`.

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

When `burst = 1`, the instruction still arrives over SPI, but operand payload bytes move over the dedicated `ui_in[7:0]` bus using `in_valid`/`in_ready`. Results return on `uo_out[7:0]` with `out_valid`/`out_ready`.

This mode is intended for streaming workloads, especially accumulate chains where the host repeatedly feeds one new operand while reusing `ACC` as the first operand.

## Microarchitecture

The design is intentionally area-driven rather than throughput-driven:

- shared add/sub significand core
- exponent align/add/subtract logic
- normalize and round stage
- iterative multiply/divide sequencer
- 16-bit `ACC` register for chaining results
- transport handlers for SPI and burst I/O

The spec's first-order estimate places the full design at roughly `1110` gate equivalents before place-and-route overhead, which is why it recommends budgeting for a `2x2` Tiny Tapeout footprint rather than a single tile.

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

The spec is substantially more complete than the current RTL. In particular:

- the top-level source in [src/project.v](src/project.v) is still an early scaffold
- `info.yaml` and [docs/info.md](docs/info.md) are still template content
- the existing tests focus mainly on the current SPI receive path, not the full arithmetic datapath defined in the spec

So this repository should currently be read as "design specification plus early implementation work", not as a finished Tiny Tapeout submission.
