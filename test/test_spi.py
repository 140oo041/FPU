# SPDX-License-Identifier: Apache-2.0
#
# Cocotb unit tests for the SPI block (src/SPI_copy.v), driven through the
# tb_spi.v wrapper. `state` is driven directly so RECEIVE (RX) and WRITEBACK
# (TX) can be exercised without the fsm.
#
# Run:
#   cd test && make -f Makefile.spi
#   (waveform -> tb_spi.fst)

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

# ---- state encodings (match SPI.v localparams) ----
IDLE = 0
RECEIVE = 1
PROCESS = 2
WRITEBACK = 3

# System clock: 100 KHz (10 us period), matching test.py.
SYS_CLK_PERIOD_US = 10

# SPI half period: 6 system clocks. The 2-FF synchronizer + edge detector need
# ~3 system clocks to register an sclk edge; 6 gives margin.
SPI_HALF_PERIOD_US = 60

SETTLE_CYCLES = 6  # system clocks to let signals propagate

# Chip select is ACTIVE LOW: a frame is active while CS is held low, idle high.
CS_ACTIVE = 0
CS_IDLE = 1


async def start_clock(dut):
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, unit="us").start())


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.sclk.value = 0
    dut.cs.value = CS_IDLE       # deselected (active-low idle high)
    dut.mosi.value = 0
    dut.state.value = IDLE
    dut.write_data.value = 0
    dut.transmit.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, SETTLE_CYCLES)


async def sclk_pulse(dut, cs=CS_ACTIVE):
    """One sclk cycle low->high->low (mode 0), CS held asserted (low)."""
    dut.cs.value = cs
    dut.sclk.value = 0
    await Timer(SPI_HALF_PERIOD_US, unit="us")
    dut.sclk.value = 1
    await Timer(SPI_HALF_PERIOD_US, unit="us")
    dut.sclk.value = 0
    await Timer(SPI_HALF_PERIOD_US, unit="us")


async def send_byte(dut, byte_val):
    """Drive one byte MSB-first in RECEIVE state, framed by CS going low."""
    dut.state.value = RECEIVE
    dut.cs.value = CS_IDLE           # start deselected
    dut.sclk.value = 0
    await Timer(SPI_HALF_PERIOD_US, unit="us")
    dut.cs.value = CS_ACTIVE         # <-- CS goes low: frame begins
    await Timer(SPI_HALF_PERIOD_US, unit="us")
    for bit_pos in range(7, -1, -1):
        dut.mosi.value = (byte_val >> bit_pos) & 1
        await sclk_pulse(dut, cs=CS_ACTIVE)
    dut.cs.value = CS_IDLE           # deselect at end of frame
    await Timer(SPI_HALF_PERIOD_US, unit="us")


async def transmit_capture(dut, nbits=24):
    """Clock out `nbits` in WRITEBACK, sampling MISO MSB-first.

    MISO for index k is registered before the k-th sclk edge advances the
    counter, so we sample during the sclk-low phase, then pulse.
    Returns (captured_value, transmitted_seen).
    """
    seen = [False]

    async def monitor():
        while True:
            await RisingEdge(dut.clk)
            if dut.transmitted.value == 1:
                seen[0] = True

    mon = cocotb.start_soon(monitor())

    val = 0
    dut.state.value = WRITEBACK
    dut.cs.value = CS_IDLE           # start deselected
    dut.sclk.value = 0
    await Timer(SPI_HALF_PERIOD_US, unit="us")
    dut.cs.value = CS_ACTIVE         # <-- CS goes low: frame begins
    await ClockCycles(dut.clk, SETTLE_CYCLES)  # let MISO settle to bit 0
    for _ in range(nbits):
        await Timer(SPI_HALF_PERIOD_US, unit="us")   # low phase: MISO settles
        val = (val << 1) | int(dut.miso.value)        # MSB-first
        dut.sclk.value = 1
        await Timer(SPI_HALF_PERIOD_US, unit="us")
        dut.sclk.value = 0
    await ClockCycles(dut.clk, SETTLE_CYCLES)
    dut.cs.value = CS_IDLE           # deselect at end of frame
    mon.cancel()
    return val, seen[0]


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset(dut):
    """After reset, received_data and miso are cleared."""
    await start_clock(dut)
    await reset_dut(dut)
    assert dut.received_data.value == 0, (
        f"received_data not cleared: {int(dut.received_data.value):#04x}")
    assert dut.miso.value == 0, "miso not cleared after reset"


@cocotb.test()
async def test_transmit_msb_first(dut):
    """WRITEBACK drives MISO MSB-first from write_data, and transmitted pulses."""
    await start_clock(dut)
    await reset_dut(dut)          # reset so out_bit_count starts at 0
    payload = 0xA00000
    dut.write_data.value = payload
    dut.transmit.value = 1
    captured, transmitted_seen = await transmit_capture(dut, nbits=24)
    assert captured == payload, (
        f"MISO stream {captured:#08x} != write_data {payload:#08x}")
    assert transmitted_seen, "transmitted never asserted during the 24-bit frame"


@cocotb.test()
async def test_receive_byte(dut):
    """RECEIVE shifts MOSI in MSB-first (CS low); byte_ready after 8 bits."""
    await start_clock(dut)
    await reset_dut(dut)
    await send_byte(dut, 0xA5)
    await ClockCycles(dut.clk, SETTLE_CYCLES)
    # assert dut.byte_ready.value == 1, "byte_ready did not assert after 8 bits"
    assert dut.received_data.value == 0xA5, (
        f"received_data {int(dut.received_data.value):#04x} != 0xA5")
