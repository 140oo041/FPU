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
        if fb:  # If the MSB of the previous CRC is set
            new_crc = crc ^ 0x17  # XOR with the polynomial (x^8+ x^4+ x^2 + x + 1)
        crc = ((new_crc << 1) | fb) & 0xFF
    return crc

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
    Tests 5'b10111000 .
    """
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, units="us").start())
    await reset_dut(dut)
    spi = dut.user_project.spi_inst

    TEST_BYTE = 0xB8  # 1011_1000
    calculated_crc = await calculate_CRC(dut, TEST_BYTE)
    dut._log.info(f"Calculated CRC for 0x{TEST_BYTE:02X} is 0b{calculated_crc:03b}")
    NEW_BYTE = TEST_BYTE | calculated_crc  # Append CRC to the byte

    await send_byte(dut, NEW_BYTE)
    await ClockCycles(dut.clk, SETTLE_CYCLES)

    received = int(spi.received_data.value)
    dut._log.info(f"sent=0x{NEW_BYTE:02X}  received_data=0x{received:02X}")
    assert received == NEW_BYTE, f"Expected 0x{NEW_BYTE:02X}, got 0x{received:02X}"

    hardware_crc = int(spi.crc_inst.crc.value)
    dut._log.info(f"Hardware CRC received: 0b{hardware_crc:03b}")
    assert hardware_crc == 0, f"Expected CRC 0b{calculated_crc:03b}, got 0b{hardware_crc:03b}"

    TEST_BYTE = 0xB8  # 1011_1000
    calculated_crc = await calculate_CRC(dut, TEST_BYTE)
    dut._log.info(f"Calculated CRC for 0x{TEST_BYTE:02X} is 0b{calculated_crc:03b}")
    NEW_BYTE = TEST_BYTE  # Append CRC to the byte

    await send_byte(dut, NEW_BYTE)
    await ClockCycles(dut.clk, SETTLE_CYCLES)

    received = int(spi.received_data.value)
    dut._log.info(f"sent=0x{NEW_BYTE:02X}  received_data=0x{received:02X}")
    assert received == NEW_BYTE, f"Expected 0x{NEW_BYTE:02X}, got 0x{received:02X}"

    hardware_crc = int(spi.crc_inst.crc.value)
    dut._log.info(f"Hardware CRC received: 0b{hardware_crc:03b}")
    assert hardware_crc == calculated_crc, f"Expected CRC 0b{calculated_crc:03b}, got 0b{hardware_crc:03b}"

    spi_set(dut)
    dut._log.info("PASS")


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


    for test_byte in test_cases:
        calculated_crc = await calculate_CRC(dut, test_byte)
        NEW_BYTE = test_byte | calculated_crc  # Append CRC to the byte
        await send_byte(dut, NEW_BYTE)
        await ClockCycles(dut.clk, SETTLE_CYCLES)

        received = int(spi.received_data.value)
        dut._log.info(f"sent=0x{NEW_BYTE:02X}  received_data=0x{received:02X}")
        assert received == NEW_BYTE, f"Expected 0x{NEW_BYTE:02X}, got 0x{received:02X}"
        hardware_crc = int(spi.crc_inst.crc.value)
        assert hardware_crc == 0, f"Expected CRC 0b{calculated_crc:03b}, got 0b{hardware_crc:03b}"

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
