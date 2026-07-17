# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from cocotb.utils import get_sim_time

# System clock: 100 KHz (10 us period)
SYS_CLK_PERIOD_US = 10

# SPI clock: ~8.3 KHz (120 us period = 12 system clocks per half-period).
# The synchronizer + edge detector need 3 system clocks to register a sclk
# edge, so we need at least 3 sys clocks per half-period. 6 gives safe margin.
SPI_HALF_PERIOD_US = 60

SETTLE_CYCLES = 5  # system clocks to wait after last sclk edge for signals to propagate


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def spi_set(dut, *, cs=0, mosi=0, sclk=0):
    """Drive SPI signals on uio_in: cs=bit0, mosi=bit1, sclk=bit3."""
    dut.uio_in.value = (cs & 1) | ((mosi & 1) << 1) | ((sclk & 1) << 3)


async def spi_edge(dut, mosi_bit, cs=1):
    """One complete sclk cycle: low → high → low, holding MOSI stable."""
    spi_set(dut, cs=cs, mosi=mosi_bit, sclk=0)
    await Timer(SPI_HALF_PERIOD_US, units="us")
    spi_set(dut, cs=cs, mosi=mosi_bit, sclk=1)
    await Timer(SPI_HALF_PERIOD_US, units="us")
    spi_set(dut, cs=cs, mosi=mosi_bit, sclk=0)
    await Timer(SPI_HALF_PERIOD_US, units="us")

async def spi_idle(dut, time, cs=1):
    """Clock idle bits for a given time in us: sclk toggling, mosi held at 0."""
    for _ in range(time // (3 * SPI_HALF_PERIOD_US)):
        await spi_edge(dut, mosi_bit=0, cs=cs)


async def reset_dut(dut):
    """Apply an active-low reset and return with all SPI pins idle."""
    dut.ena.value = 1
    dut.ui_in.value = 0
    spi_set(dut)
    dut.rst_n.value = 0
    dut._log.info("Resetting DUT...")
    await ClockCycles(dut.clk, 10)
    dut._log.info("Reset DUT...")
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, SETTLE_CYCLES)


async def send_byte(dut, byte_val):
    """Send 8 bits MSB-first with CS asserted throughout."""
    spi_set(dut, cs=1, sclk=0)
    await Timer(SPI_HALF_PERIOD_US, units="us")
    for bit_pos in range(7, -1, -1):
        await spi_edge(dut, mosi_bit=(byte_val >> bit_pos) & 1, cs=1)

async def calculate_CRC(dut, byte_val):
    """Calculate the CRC for a given byte value."""
    crc = 0xFF  # Initial CRC value
    
    for bit_pos in range(7, -1, -1):
        mosi_bit = (byte_val >> bit_pos) & 1
        fb = (crc >> 7) ^ mosi_bit  # Feedback bit
        new_crc = crc
        if fb:  # If the MSB of the previous CRC is set
            new_crc = crc ^ 0x17  # XOR with the polynomial (x^8+ x^4+ x^2 + x + 1)
        crc = ((new_crc << 1) | fb) & 0xFF
    return crc^0xFF

async def calculate_CRC_list(dut, bytes:list[int]):
    """Calculate the CRC for a given byte value."""
    crc = 0xFF  # Initial CRC value
    for byte_val in bytes:
        for bit_pos in range(7, -1, -1):
            mosi_bit = (byte_val >> bit_pos) & 1
            fb = (crc >> 7) ^ mosi_bit  # Feedback bit
            new_crc = crc
            if fb:  # If the MSB of the previous CRC is set
                new_crc = crc ^ 0x17  # XOR with the polynomial (x^8+ x^4+ x^2 + x + 1)
            crc = ((new_crc << 1) | fb) & 0xFF
    return crc^0xFF



# ---------------------------------------------------------------------------
# Opcode
# ---------------------------------------------------------------------------
#
# Command byte layout (see project.v: op=opcode[7:5], acc=opcode[4]):
#
#   bit   7 6 5   4     3 2 1 0
#         opcode  acc   unused
#
# Each helper returns the list of bytes to stream over SPI, MSB-first, with
# 16-bit operands packed low-byte-first to match the existing `add` frame and
# the received_data ordering in project.v.
#
#   000 ADD  a, b   a + b        float add; align exponents, add, normalize, RNE.
#   001 SUB  a, b   a - b        add with b's sign flipped.
#   010 MUL  a, b   a * b        add exponents, multiply significands, normalize.
#   011 DIV  a, b   a / b        subtract exponents, iterative divide; b=0 -> NaN.
#   100 NEG  a      -a           unary; flip sign bit only.
#   101 ABS  a      |a|          unary; clear sign bit.
#   110 SLT  a, b   (a<b)?1.0:0.0 set-less-than; returns float 1.0 or 0.0.
#   111 NOP  --     ACC unchanged no operands, no write; status read-back/padding.

OP_ADD = 0b000
OP_SUB = 0b001
OP_MUL = 0b010
OP_DIV = 0b011
OP_NEG = 0b100
OP_ABS = 0b101
OP_SLT = 0b110
OP_NOP = 0b111

ACC_BIT = 0x10  # opcode[4]


def _cmd_byte(op, accumulate=False):
    """Build the command byte: opcode in bits [7:5], acc in bit [4]."""
    byte = (op & 0x7) << 5
    if accumulate:
        byte |= ACC_BIT
    return byte


def _pack16(value):
    """Pack a 16-bit operand into [low_byte, high_byte]."""
    return [(value >> 8) & 0xFF,value & 0xFF]


def _binary_op(op, op1, op2, accumulate=False):
    """Frame for a two-operand opcode: cmd, op1(lo,hi), op2(lo,hi)."""
    return [_cmd_byte(op, accumulate) | 0x06] + _pack16(op1) + _pack16(op2)


def _unary_op(op, op1, accumulate=False):
    """Frame for a one-operand opcode: cmd, op1(lo,hi)."""
    return [_cmd_byte(op, accumulate) | 0x04] + _pack16(op1)


def add(dut, op1, op2, accumulate: bool = False):
    """000 ADD: a + b."""
    return _binary_op(OP_ADD, op1, op2, accumulate)


def sub(dut, op1, op2, accumulate: bool = False):
    """001 SUB: a - b (add with b's sign flipped)."""
    return _binary_op(OP_SUB, op1, op2, accumulate)


def mul(dut, op1, op2, accumulate: bool = False):
    """010 MUL: a * b."""
    return _binary_op(OP_MUL, op1, op2, accumulate)


def div(dut, op1, op2, accumulate: bool = False):
    """011 DIV: a / b (b == 0 -> NaN)."""
    return _binary_op(OP_DIV, op1, op2, accumulate)


def neg(dut, op1, accumulate: bool = False):
    """100 NEG: -a (unary; flip sign bit only)."""
    return _unary_op(OP_NEG, op1, accumulate)


def abs_(dut, op1, accumulate: bool = False):
    """101 ABS: |a| (unary; clear sign bit)."""
    return _unary_op(OP_ABS, op1, accumulate)


def slt(dut, op1, op2, accumulate: bool = False):
    """110 SLT: (a < b) ? 1.0 : 0.0."""
    return _binary_op(OP_SLT, op1, op2, accumulate)


def nop(dut):
    """111 NOP: no operands, no write (status read-back / padding)."""
    return [_cmd_byte(OP_NOP)]


# ---------------------------------------------------------------------------
# Float
# ---------------------------------------------------------------------------

def float_to_bits(f):
    """Convert a Python float to its 16-bit bfloat16 bit pattern.

    bfloat16 is just the high 16 bits of an IEEE-754 float32
    (sign[1] | exp[8] | mant[7]), so we truncate to those 16 bits.
    """
    import struct
    int_repr = struct.unpack('>I', struct.pack('>f', f))[0]
    return (int_repr >> 16) & 0xFFFF


def bits_to_float(b):
    """Convert a 16-bit bfloat16 bit pattern back to a Python float.

    bfloat16 sits in the high 16 bits of a float32, so we zero-extend the low
    16 mantissa bits and reinterpret as float32.
    """
    import struct
    return struct.unpack('>f', struct.pack('>I', (b & 0xFFFF) << 16))[0]



# ---------------------------------------------------------------------------
# Markers
# ---------------------------------------------------------------------------

_GTKW = os.path.join(os.path.dirname(__file__), "tb.gtkw")
_markers = []  # list of sim-times in ps, max 26 (A-Z)


def mark(dut, label=""):
    """Record a named GTKWave marker at the current sim time."""
    t_ps = get_sim_time(units="ps")
    _markers.append(t_ps)
    dut._log.info(f"MARKER {label or len(_markers)} @ {t_ps} ps")


def write_markers():
    """Patch the '*' line of tb.gtkw with the recorded marker positions."""
    if not _markers:
        return
    # primary marker = first one; named markers A..Z = up to 26
    primary = int(_markers[0])
    named = (_markers[:26] + [-1] * 26)[:26]
    fields = [str(int(x)) if x != -1 else "-1" for x in named]
    star = f"*-24.0 {primary} " + " ".join(fields)
    with open(_GTKW) as f:
        lines = f.readlines()
    for i, ln in enumerate(lines):
        if ln.startswith("*"):
            lines[i] = star + "\n"
            break
    with open(_GTKW, "w") as f:
        f.writelines(lines)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset_state(dut):
    """received_data and data_ready must both be 0 immediately after reset."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    assert int(spi.received_data.value) == 0, "received_data should be 0 after reset"
    assert int(spi.data_ready.value) == 0, "data_ready should be 0 after reset"
    dut._log.info("PASS")


@cocotb.test()
async def test_data_ready_timing(dut):
    """
    8 bits are sent on edges 0-7 (MSB first).
    data_ready must be 0 for edges 0-6 and assert on edge 7 (the last bit).
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    spi_set(dut, cs=1, sclk=0)
    await Timer(SPI_HALF_PERIOD_US, units="us")

    # Edges 0-6: data_ready must stay low
    for edge_num in range(7):
        dut._log.info(f"Start of edge {edge_num}")
        await spi_edge(dut, mosi_bit=1, cs=1)
        await ClockCycles(dut.clk, SETTLE_CYCLES)
        assert int(spi.data_ready.value) == 0, \
            f"data_ready should be 0 after edge {edge_num}"

    # Edge 7: last bit clocked in, data_ready asserts
    await spi_edge(dut, mosi_bit=1, cs=1)
    await ClockCycles(dut.clk, SETTLE_CYCLES)
    assert int(spi.data_ready.value) == 1, \
        "data_ready should be 1 after edge 7 (all 8 bits received)"


    # await ClockCycles(dut.clk, 2000*SETTLE_CYCLES)
    spi_set(dut)
    dut._log.info("PASS")


@cocotb.test()
async def test_full_byte_received(dut):
    """
    After 8 sclk edges the complete byte is present in received_data.
    Tests 0xA5 (alternating bits) to catch wiring and bit-order bugs.
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    TEST_BYTE = 0xA5  # 1010_0101

    await send_byte(dut, TEST_BYTE)
    await ClockCycles(dut.clk, SETTLE_CYCLES)

    received = int(spi.received_data.value)
    dut._log.info(f"sent=0x{TEST_BYTE:02X}  received_data=0x{received:02X}")
    assert received == TEST_BYTE, f"Expected 0x{TEST_BYTE:02X}, got 0x{received:02X}"

    spi_set(dut)
    dut._log.info("PASS")

@cocotb.test()
async def test_full_byte_received_CRC(dut):
    """
    After 8 sclk edges the complete byte is present in received_data.
    Tests 8'b10111000 .
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    TEST_BYTE = 0xB8  # 1011_1000
    calculated_crc = await calculate_CRC(dut, TEST_BYTE)
    dut._log.info(f"Calculated CRC for 0x{TEST_BYTE:02X} is 0x{calculated_crc:02X}")


    await send_byte(dut, TEST_BYTE)
    await send_byte(dut, calculated_crc)  # Send the calculated CRC byte
    spi_set(dut, cs=0, sclk=0)
    mark(dut, f"After sending 0x{TEST_BYTE:02X} and CRC 0x{calculated_crc:02X}")

    await ClockCycles(dut.clk, SETTLE_CYCLES)

    received = int(dut.user_project.opcode)
    dut._log.info(f"sent=0x{TEST_BYTE:02X}  received_data=0x{received:02X}")
    assert received == TEST_BYTE, f"Expected 0x{TEST_BYTE:02X}, got 0x{received:02X}"

    hardware_crc = int(spi.crc_inst.crc.value)
    dut._log.info(f"Hardware CRC received: 0x{hardware_crc^0xFF:02X}")
    assert hardware_crc^0xFF == 0xBD, f"Expected CRC 0x{calculated_crc:02X}, got 0x{hardware_crc:02X}"

    spi_set(dut)
    dut._log.info("PASS")
    write_markers()  # Update GTKWave markers for this test


@cocotb.test()
async def test_cs_gates_shift_register(dut):
    """
    With CS de-asserted, the shift register must not capture any bits
    and data_ready must remain 0 regardless of sclk activity.
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    spi_set(dut, cs=0, mosi=1, sclk=0)
    for _ in range(8):
        await spi_edge(dut, mosi_bit=1, cs=0)

    await ClockCycles(dut.clk, SETTLE_CYCLES)
    assert int(spi.received_data.value) == 0, "received_data must stay 0 when CS=0"
    assert int(spi.data_ready.value) == 0, "data_ready must stay 0 when CS=0"

    spi_set(dut)
    dut._log.info("PASS")


@cocotb.test()
async def test_multiple_bytes(dut):
    """
    Send five bytes back-to-back (counter naturally wraps to 0 after each
    8-bit transfer, so no reset is needed between bytes).
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    test_cases = [0xA5, 0x3C, 0xFF, 0x10, 0x55]

    for test_byte in test_cases:
        await send_byte(dut, test_byte)
        await ClockCycles(dut.clk, SETTLE_CYCLES)

        mark(dut, f"After sending 0x{test_byte:02X}")
        received = int(spi.received_data.value)
        dut._log.info(f"sent=0x{test_byte:02X}  received_data=0x{received:02X}")
        assert received == test_byte, f"Expected 0x{test_byte:02X}, got 0x{received:02X}"

    write_markers()  # Update GTKWave markers for this test
    spi_set(dut)
    dut._log.info("PASS")

@cocotb.test()
async def test_multiple_bytes_CRC(dut):
    """
    Send five bytes back-to-back (counter naturally wraps to 0 after each
    8-bit transfer, so no reset is needed between bytes).
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    test_cases = [0xA8, 0x38, 0xF8, 0x10, 0x58]  # Example bytes for CRC testing
    calculated_crc = await calculate_CRC_list(dut, test_cases)

    for test_byte in test_cases:
        await send_byte(dut, test_byte)
        await ClockCycles(dut.clk, SETTLE_CYCLES)

        received = int(spi.received_data.value)
        dut._log.info(f"sent=0x{test_byte:02X}  received_data=0x{received:02X}")
        assert received == test_byte, f"Expected 0x{test_byte:02X}, got 0x{received:02X}"

    await send_byte(dut, calculated_crc)  # Send the calculated CRC byte
    await ClockCycles(dut.clk, SETTLE_CYCLES)

    hardware_crc = int(spi.crc_inst.crc.value)
    assert hardware_crc^0xFF == 0xBD, f"Expected CRC 0x{calculated_crc:02X}, got 0x{hardware_crc:02X}"

    spi_set(dut)
    dut._log.info("PASS")


@cocotb.test()
async def test_cs_deassert_clears_data_ready(dut):
    """
    data_ready depends on cs_sync: de-asserting CS after 8 edges must
    immediately pull data_ready low.
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    spi_set(dut, cs=1, sclk=0)
    await Timer(SPI_HALF_PERIOD_US, units="us")

    # 8 edges to assert data_ready
    for _ in range(8):
        await spi_edge(dut, mosi_bit=0, cs=1)
    await ClockCycles(dut.clk, SETTLE_CYCLES)
    assert int(spi.data_ready.value) == 1, \
        "data_ready should be 1 after 8 edges (precondition)"

    # De-assert CS; data_ready = (bit_count==7) & cs_sync, so it must go 0
    spi_set(dut, cs=0, sclk=0)
    await ClockCycles(dut.clk, SETTLE_CYCLES)
    assert int(spi.data_ready.value) == 0, \
        "data_ready must be 0 when CS is de-asserted"

    dut._log.info("PASS")

@cocotb.test()
@cocotb.parametrize(
    # Sums chosen to be exactly representable in bfloat16 (7-bit mantissa),
    # so truncating float_to_bits agrees with the hardware's RNE result.
    (
        ("float_a", "float_b"),
        [
            (1.5, 2.5),     # 4.0
            (-2.5, 3.0),    # 0.5
            (0.0, 4.0),     # 4.0
            (48.0, 16.0),   # 64.0
            (-1.0, -1.0),   # -2.0
        ],
    ),
)
async def test_add(dut, float_a, float_b):
    """
    Stream an ADD command frame (opcode + operands + CRC) over SPI and check
    that accumulate_register holds float_a + float_b in bfloat16. Runs once per
    (float_a, float_b) pair via @cocotb.parametrize.
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    op1 = float_to_bits(float_a)
    op2 = float_to_bits(float_b)

    dut._log.info(f"Testing ADD operation: {float_a} + {float_b} (op1=0x{op1:04X}, op2=0x{op2:04X})")

    test_cases = add(dut, op1, op2)  # Example add operation
    calculated_crc = await calculate_CRC_list(dut, test_cases)

    for test_byte in test_cases:
        await send_byte(dut, test_byte)
        await ClockCycles(dut.clk, SETTLE_CYCLES)

        received = int(spi.received_data.value)
        dut._log.info(f"sent=0x{test_byte:02X}  received_data=0x{received:02X}")
        assert received == test_byte, f"Expected 0x{test_byte:02X}, got 0x{received:02X}"

    await send_byte(dut, calculated_crc)  # Send the calculated CRC byte
    await ClockCycles(dut.clk, SETTLE_CYCLES)

    hardware_crc = int(spi.crc_inst.crc.value)
    assert hardware_crc^0xFF == 0xBD, f"Expected CRC 0x{calculated_crc:02X}, got 0x{hardware_crc:02X}"
    await spi_idle(dut, 20000)  # Hold SPI idle for 1000 us to ensure processing is complete
    spi_set(dut, cs=1, sclk=0)
    acc = int(dut.user_project.fpu_system_inst.accumulate_register.value)
    expected = float_to_bits(float_a + float_b)
    assert acc == expected, \
        f"Expected accumulate_register to hold the result of {float_a + float_b} i.e., 0x{expected:04X}, got 0x{acc:04X}"


    spi_set(dut)
    dut._log.info("PASS")


@cocotb.test()
@cocotb.parametrize(
    # Bug #1 (shift-amount truncation): alignment uses shift_amt = exp_diff[3:0],
    # so any exponent difference >= 16 wraps around instead of flushing the
    # smaller operand to zero. Both operands here are NONZERO and normalized, so
    # a failure isolates the shift truncation from the zero-handling bug (#2).
    #
    # Each pair's exact bfloat16 sum equals the LARGER operand: the smaller one
    # sits far below the larger's LSB, so a correct aligner drops it entirely.
    #
    #   pair              exp_diff  exp_diff[3:0]  buggy shift
    #   (65536, 1)          16          0          none  -> adds full 1.0 -> 131072
    #   (131072, 2)         16          0          none  -> 262144
    #   (1048576, 3)        19          3          >>3   -> corrupts result
    (
        ("float_a", "float_b"),
        [
            (65536.0, 1.0),      # 2^16 + 2^0,  exp_diff = 16
            (131072.0, 2.0),     # 2^17 + 2^1,  exp_diff = 16
            (1048576.0, 3.0),    # 2^20 + ~2^1, exp_diff = 19
        ],
    ),
)
async def test_add_large_exp_diff(dut, float_a, float_b):
    """
    Demonstrates bug #1: the ADD/SUB aligner truncates the shift amount to 4
    bits (shift_amt = exp_diff[3:0] in fpu_core.v), so operands whose exponents
    differ by a multiple of 16 (or more) are mis-aligned. The smaller operand
    should flush to zero; instead its significand survives and corrupts the sum.

    Expected result is exactly the larger operand; on the buggy RTL the
    accumulate_register comes out too large (e.g. 65536 + 1 -> 131072).
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    op1 = float_to_bits(float_a)
    op2 = float_to_bits(float_b)

    dut._log.info(f"Testing ADD with large exp diff: {float_a} + {float_b} "
                  f"(op1=0x{op1:04X}, op2=0x{op2:04X})")

    test_cases = add(dut, op1, op2)
    calculated_crc = await calculate_CRC_list(dut, test_cases)

    for test_byte in test_cases:
        await send_byte(dut, test_byte)
        await ClockCycles(dut.clk, SETTLE_CYCLES)

        received = int(spi.received_data.value)
        assert received == test_byte, f"Expected 0x{test_byte:02X}, got 0x{received:02X}"

    await send_byte(dut, calculated_crc)
    await ClockCycles(dut.clk, SETTLE_CYCLES)

    hardware_crc = int(spi.crc_inst.crc.value)
    assert hardware_crc ^ 0xFF == 0xBD, \
        f"Expected CRC 0x{calculated_crc:02X}, got 0x{hardware_crc:02X}"

    await Timer(1000, units="us")
    acc = int(dut.user_project.fpu_system_inst.accumulate_register.value)
    expected = float_to_bits(float_a + float_b)  # == float_to_bits(float_a)
    assert acc == expected, \
        f"exp_diff >= 16 mis-aligned: expected {float_a + float_b} " \
        f"(0x{expected:04X}), got 0x{acc:04X} " \
        f"(bug #1: shift_amt = exp_diff[3:0] truncates the alignment shift)"

    spi_set(dut)
    dut._log.info("PASS")


# ---------------------------------------------------------------------------
# Frame runner (shared by the arithmetic opcode tests below)
# ---------------------------------------------------------------------------

async def run_op_frame(dut, spi, frame):
    """Stream a command frame followed by its CRC over SPI, verifying each byte
    echoes back and the CRC residue is correct, then return the resulting
    accumulate_register bits."""
    calculated_crc = await calculate_CRC_list(dut, frame)

    for test_byte in frame:
        await send_byte(dut, test_byte)
        await ClockCycles(dut.clk, SETTLE_CYCLES)
        received = int(spi.received_data.value)
        assert received == test_byte, f"Expected 0x{test_byte:02X}, got 0x{received:02X}"

    await send_byte(dut, calculated_crc)
    await ClockCycles(dut.clk, SETTLE_CYCLES)

    hardware_crc = int(spi.crc_inst.crc.value)
    assert hardware_crc ^ 0xFF == 0xBD, \
        f"CRC residue mismatch: expected 0xBD, got 0x{hardware_crc ^ 0xFF:02X}"

    await Timer(1000, units="us")  # let the FPU compute and write back
    return int(dut.user_project.fpu_system_inst.accumulate_register.value)


@cocotb.test()
@cocotb.parametrize(
    # SUB shares the ADD aligner, so exponent differences are kept < 16 to avoid
    # bug #1. Differences are exactly representable in bfloat16.
    (
        ("float_a", "float_b"),
        [
            (5.0, 2.0),     # 3.0
            (2.5, 1.5),     # 1.0
            (-1.0, 2.0),    # -3.0
            (8.0, 0.5),     # 7.5
            (10.0, 10.0),   # 0.0
        ],
    ),
)
async def test_sub(dut, float_a, float_b):
    """001 SUB: accumulate_register must hold float_a - float_b (bfloat16)."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    op1 = float_to_bits(float_a)
    op2 = float_to_bits(float_b)
    dut._log.info(f"Testing SUB: {float_a} - {float_b} (op1=0x{op1:04X}, op2=0x{op2:04X})")

    acc = await run_op_frame(dut, spi, sub(dut, op1, op2))
    expected = float_to_bits(float_a - float_b)
    assert acc == expected, \
        f"SUB {float_a} - {float_b}: expected {float_a - float_b} " \
        f"(0x{expected:04X}), got {bits_to_float(acc)} (0x{acc:04X})"

    spi_set(dut)
    dut._log.info("PASS")


@cocotb.test()
@cocotb.parametrize(
    # Products chosen to be exactly representable in bfloat16 (7-bit mantissa),
    # so truncating float_to_bits matches the hardware result.
    (
        ("float_a", "float_b"),
        [
            (2.0, 4.0),     # 8.0
            (1.5, 2.0),     # 3.0
            (-3.0, 2.0),    # -6.0
            (0.5, 0.5),     # 0.25
            (1.25, 4.0),    # 5.0
        ],
    ),
)
async def test_mul(dut, float_a, float_b):
    """010 MUL: accumulate_register must hold float_a * float_b (bfloat16)."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    op1 = float_to_bits(float_a)
    op2 = float_to_bits(float_b)
    dut._log.info(f"Testing MUL: {float_a} * {float_b} (op1=0x{op1:04X}, op2=0x{op2:04X})")

    acc = await run_op_frame(dut, spi, mul(dut, op1, op2))
    expected = float_to_bits(float_a * float_b)
    assert acc == expected, \
        f"MUL {float_a} * {float_b}: expected {float_a * float_b} " \
        f"(0x{expected:04X}), got {bits_to_float(acc)} (0x{acc:04X})"

    spi_set(dut)
    dut._log.info("PASS")


# Relative tolerance for DIV: the divider uses an 8-bit reciprocal LUT (and
# clamps 1/1.0 to 255/256), so the quotient is approximate. Two 7-bit-mantissa
# ULPs (~1.6%) covers the reciprocal + rounding error.
DIV_REL_TOL = 2.0 / 128.0


@cocotb.test()
@cocotb.parametrize(
    (
        ("float_a", "float_b"),
        [
            (8.0, 2.0),     # 4.0
            (6.0, 2.0),     # 3.0
            (1.0, 4.0),     # 0.25
            (-8.0, 4.0),    # -2.0
            (9.0, 3.0),     # 3.0
        ],
    ),
)
async def test_div(dut, float_a, float_b):
    """011 DIV: accumulate_register must hold float_a / float_b within the
    reciprocal-LUT tolerance (division is approximate, so compare as floats)."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    op1 = float_to_bits(float_a)
    op2 = float_to_bits(float_b)
    dut._log.info(f"Testing DIV: {float_a} / {float_b} (op1=0x{op1:04X}, op2=0x{op2:04X})")

    acc = await run_op_frame(dut, spi, div(dut, op1, op2))
    result = bits_to_float(acc)
    expected = float_a / float_b
    tol = abs(expected) * DIV_REL_TOL
    assert abs(result - expected) <= tol, \
        f"DIV {float_a} / {float_b}: expected ~{expected}, got {result} " \
        f"(0x{acc:04X}), tol=±{tol}"

    spi_set(dut)
    dut._log.info("PASS")




@cocotb.test()
@cocotb.parametrize(
    ("float_a", [1.5, -2.5, 3.0, -0.5, 0.0]),
)
async def test_neg(dut, float_a):
    """100 NEG: unary; accumulate_register must hold -float_a (sign bit flipped)."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    op1 = float_to_bits(float_a)
    dut._log.info(f"Testing NEG: -({float_a}) (op1=0x{op1:04X})")

    acc = await run_op_frame(dut, spi, neg(dut, op1))
    expected = float_to_bits(-float_a)   # NEG only flips bit 15
    assert acc == expected, \
        f"NEG {float_a}: expected {-float_a} (0x{expected:04X}), got 0x{acc:04X}"

    spi_set(dut)
    dut._log.info("PASS")


@cocotb.test()
@cocotb.parametrize(
    ("float_a", [1.5, -2.5, 3.0, -0.5, -0.0]),
)
async def test_abs(dut, float_a):
    """101 ABS: unary; accumulate_register must hold |float_a| (sign bit cleared)."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    op1 = float_to_bits(float_a)
    dut._log.info(f"Testing ABS: |{float_a}| (op1=0x{op1:04X})")

    acc = await run_op_frame(dut, spi, abs_(dut, op1))
    expected = float_to_bits(abs(float_a))   # ABS clears bit 15
    assert acc == expected, \
        f"ABS {float_a}: expected {abs(float_a)} (0x{expected:04X}), got 0x{acc:04X}"

    spi_set(dut)
    dut._log.info("PASS")


@cocotb.test()
@cocotb.parametrize(
    # Covers every SLT branch: opposite signs, both positive, both negative, equal.
    (
        ("float_a", "float_b"),
        [
            (1.0, 2.0),     # a<b  -> 1.0   (both positive)
            (2.0, 1.0),     # a>b  -> 0.0
            (-1.0, 2.0),    # a<b  -> 1.0   (opposite signs)
            (2.0, -1.0),    # a>b  -> 0.0   (opposite signs)
            (-2.0, -1.0),   # a<b  -> 1.0   (both negative)
            (-1.0, -2.0),   # a>b  -> 0.0   (both negative)
            (3.0, 3.0),     # a==b -> 0.0
        ],
    ),
)
async def test_slt(dut, float_a, float_b):
    """110 SLT: accumulate_register must hold 1.0 (0x3F80) if a<b else 0.0."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    op1 = float_to_bits(float_a)
    op2 = float_to_bits(float_b)
    dut._log.info(f"Testing SLT: ({float_a} < {float_b}) (op1=0x{op1:04X}, op2=0x{op2:04X})")

    acc = await run_op_frame(dut, spi, slt(dut, op1, op2))
    expected = 0x3F80 if float_a < float_b else 0x0000
    assert acc == expected, \
        f"SLT {float_a} < {float_b} is {float_a < float_b}: " \
        f"expected 0x{expected:04X}, got 0x{acc:04X}"

    spi_set(dut)
    dut._log.info("PASS")


@cocotb.test()
async def test_nop_no_writeback(dut):
    """111 NOP: no operands, no accumulate write. From the reset state the
    accumulate_register must stay 0 and result_ready must never assert (NOP
    drives accumulate_enable = 0)."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst
    fpu = dut.user_project.fpu_system_inst

    assert int(fpu.accumulate_register.value) == 0, "precondition: acc reg starts at 0"

    await run_op_frame(dut, spi, nop(dut))

    acc = int(fpu.accumulate_register.value)
    rr = int(fpu.result_ready.value)
    dut._log.info(f"After NOP: acc=0x{acc:04X}  result_ready={rr}")
    assert acc == 0, f"NOP must not modify accumulate_register, got 0x{acc:04X}"
    assert rr == 0, "NOP must not assert result_ready (no write-back)"

    spi_set(dut)
    dut._log.info("PASS")
