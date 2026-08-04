"""Gate-level tests using only the Tiny Tapeout top-level interface.

The synthesized netlist does not preserve RTL instance names such as
``spi_inst`` or ``fpu_system_inst``.  Tests in this module therefore interact
with the design exactly as external hardware does: through its clock, reset,
and I/O pins.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


SYS_CLK_PERIOD_US = 10
SPI_HALF_PERIOD_US = 60
SETTLE_CYCLES = 8

CS_PIN = 0
MOSI_PIN = 1
MISO_PIN = 2
SCLK_PIN = 3

OP_ADD = 0b000
OP_SUB = 0b001
OP_MUL = 0b010
OP_DIV = 0b011
OP_NEG = 0b100
OP_ABS = 0b101
OP_SLT = 0b110


def drive_spi(dut, *, selected=False, mosi=0, sclk=0):
    """Drive active-low CS, MOSI, and SCLK through ``uio_in``."""
    cs_n = 0 if selected else 1
    dut.uio_in.value = (
        (cs_n << CS_PIN)
        | ((mosi & 1) << MOSI_PIN)
        | ((sclk & 1) << SCLK_PIN)
    )


async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    drive_spi(dut)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, SETTLE_CYCLES)


async def spi_bit(dut, bit):
    """Clock one Mode-0, MSB-first input bit while CS remains asserted."""
    drive_spi(dut, selected=True, mosi=bit, sclk=0)
    await Timer(SPI_HALF_PERIOD_US, unit="us")
    drive_spi(dut, selected=True, mosi=bit, sclk=1)
    await Timer(SPI_HALF_PERIOD_US, unit="us")
    drive_spi(dut, selected=True, mosi=bit, sclk=0)
    await Timer(SPI_HALF_PERIOD_US, unit="us")


async def send_byte(dut, value):
    for bit_index in range(7, -1, -1):
        await spi_bit(dut, (value >> bit_index) & 1)


def crc8_autosar(values):
    """Return CRC-8/AUTOSAR (poly 0x2f, init/xor-out 0xff)."""
    crc = 0xFF
    for value in values:
        crc ^= value
        for _ in range(8):
            if crc & 0x80:
                crc = ((crc << 1) ^ 0x2F) & 0xFF
            else:
                crc = (crc << 1) & 0xFF
    return crc ^ 0xFF


def build_request(opcode, operands, *, binary, tag=0):
    command = (
        ((opcode & 0x7) << 5)
        | ((1 if binary else 0) << 3)
        | (tag & 0x7)
    )
    request = [command]
    for operand in operands:
        request.extend([(operand >> 8) & 0xFF, operand & 0xFF])
    request.append(crc8_autosar(request))
    return request


async def read_response(dut):
    """Read the 24-bit response in a separately CS-framed transaction."""
    drive_spi(dut, selected=False, sclk=0)
    await ClockCycles(dut.clk, SETTLE_CYCLES)
    drive_spi(dut, selected=True, sclk=0)
    await ClockCycles(dut.clk, SETTLE_CYCLES)

    response = 0
    for _ in range(24):
        drive_spi(dut, selected=True, mosi=0, sclk=0)
        await Timer(SPI_HALF_PERIOD_US, unit="us")
        miso = (int(dut.uio_out.value) >> MISO_PIN) & 1
        response = (response << 1) | miso
        drive_spi(dut, selected=True, mosi=0, sclk=1)
        await Timer(SPI_HALF_PERIOD_US, unit="us")
        drive_spi(dut, selected=True, mosi=0, sclk=0)
        await Timer(SPI_HALF_PERIOD_US, unit="us")

    drive_spi(dut, selected=False, sclk=0)
    return response


async def execute_request(dut, request):
    drive_spi(dut, selected=False, sclk=0)
    await ClockCycles(dut.clk, SETTLE_CYCLES)
    drive_spi(dut, selected=True, sclk=0)
    await ClockCycles(dut.clk, SETTLE_CYCLES)
    for byte in request:
        await send_byte(dut, byte)

    # Give the FPU time to commit the result before starting readback.
    await ClockCycles(dut.clk, 100)
    return await read_response(dut)


@cocotb.test()
async def test_top_level_reset_and_pin_directions(dut):
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, unit="us").start())
    await reset_dut(dut)

    assert int(dut.uo_out.value) == 0
    assert int(dut.uio_oe.value) == (1 << MISO_PIN)
    assert ((int(dut.uio_out.value) >> MISO_PIN) & 1) == 0


@cocotb.test()
@cocotb.parametrize(
    (
        ("case_name", "opcode", "binary", "operands", "tag", "expected_result"),
        [
            ("add", OP_ADD, True, (0x3F80, 0x4000), 0, 0x4040),
            ("subtract", OP_SUB, True, (0x40A0, 0x4000), 1, 0x4040),
            ("multiply", OP_MUL, True, (0x4000, 0x4080), 2, 0x4100),
            ("negate", OP_NEG, False, (0x4040,), 3, 0xC040),
            ("absolute", OP_ABS, False, (0xC020,), 4, 0x4020),
            ("less_than", OP_SLT, True, (0x3F80, 0x4000), 5, 0x3F80),
            ("negative_add", OP_ADD, True, (0xBF80, 0xBF80), 6, 0xC000),
            ("zero_add", OP_ADD, True, (0x0000, 0x4080), 7, 0x4080),
        ],
    ),
)
async def test_arithmetic_readback_through_top_level_spi(
    dut, case_name, opcode, binary, operands, tag, expected_result
):
    """Exercise clean arithmetic responses and tag echoing over chip pins."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, unit="us").start())
    await reset_dut(dut)

    request = build_request(opcode, operands, binary=binary, tag=tag)
    response = await execute_request(dut, request)

    expected_status = (tag << 5) | 0x08
    expected = (expected_status << 16) | expected_result
    assert response == expected, (
        f"{case_name}: SPI response 0x{response:06X} != expected "
        f"status/result 0x{expected:06X}"
    )


@cocotb.test()
@cocotb.parametrize(
    (
        ("case_name", "opcode", "operands", "tag", "expected_flags"),
        [
            ("nan", OP_DIV, (0x0000, 0x0000), 1, 0x09),
            ("overflow", OP_MUL, (0x7F61, 0x7F61), 2, 0x0A),
        ],
    ),
)
async def test_status_flags_through_top_level_spi(
    dut, case_name, opcode, operands, tag, expected_flags
):
    """Check arithmetic exception flags in the public status byte."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, unit="us").start())
    await reset_dut(dut)

    request = build_request(opcode, operands, binary=True, tag=tag)
    response = await execute_request(dut, request)
    status = (response >> 16) & 0xFF
    expected_status = (tag << 5) | expected_flags

    assert status == expected_status, (
        f"{case_name}: status 0x{status:02X} != expected "
        f"0x{expected_status:02X}"
    )


@cocotb.test()
async def test_bad_crc_sets_error_status_through_top_level_spi(dut):
    """A corrupted frame must set the SPI error bit in returned status."""
    cocotb.start_soon(Clock(dut.clk, SYS_CLK_PERIOD_US, unit="us").start())
    await reset_dut(dut)

    request = build_request(
        OP_ADD, (0x3F80, 0x4000), binary=True, tag=0
    )
    request[-1] ^= 0x01
    response = await execute_request(dut, request)
    status = (response >> 16) & 0xFF

    assert status == 0x18, (
        f"bad CRC returned status 0x{status:02X}; expected SPI error status 0x18"
    )
