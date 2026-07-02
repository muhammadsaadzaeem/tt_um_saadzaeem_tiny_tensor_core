import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CMD_WRITE_REG = 0xE0
CMD_READ_REG = 0xE1

REG_A00 = 0x00
REG_A01 = 0x01
REG_A10 = 0x02
REG_A11 = 0x03
REG_B00 = 0x04
REG_B01 = 0x05
REG_B10 = 0x06
REG_B11 = 0x07
REG_SHIFT = 0x08
REG_CONTROL = 0x09
REG_STATUS = 0x0A
REG_Q00 = 0x10
REG_Q01 = 0x11
REG_Q10 = 0x12
REG_Q11 = 0x13
REG_CYCLES_L = 0x14
REG_CYCLES_H = 0x15


async def reset(dut):
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def send_byte(dut, value):
    dut.ui_in.value = value & 0xFF
    dut.uio_in.value = 1
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0
    dut.ui_in.value = 0
    await RisingEdge(dut.clk)


async def write_reg(dut, addr, data):
    await send_byte(dut, CMD_WRITE_REG)
    await send_byte(dut, addr)
    await send_byte(dut, data)


async def read_reg(dut, addr):
    await send_byte(dut, CMD_READ_REG)
    await send_byte(dut, addr)
    await RisingEdge(dut.clk)
    return int(dut.uo_out.value)


def to_u8(x):
    return x & 0xFF


def relu_quant8(x, shift):
    y = max(0, x) >> shift
    return min(y, 127)


async def run_case(dut, A, B, shift):
    values = [
        (REG_A00, A[0][0]),
        (REG_A01, A[0][1]),
        (REG_A10, A[1][0]),
        (REG_A11, A[1][1]),
        (REG_B00, B[0][0]),
        (REG_B01, B[0][1]),
        (REG_B10, B[1][0]),
        (REG_B11, B[1][1]),
    ]

    for addr, value in values:
        await write_reg(dut, addr, to_u8(value))

    await write_reg(dut, REG_SHIFT, shift)
    await write_reg(dut, REG_CONTROL, 1)

    await ClockCycles(dut.clk, 20)

    status = await read_reg(dut, REG_STATUS)
    assert status & 1, f"done bit not set, status={status}"

    result = [
        await read_reg(dut, REG_Q00),
        await read_reg(dut, REG_Q01),
        await read_reg(dut, REG_Q10),
        await read_reg(dut, REG_Q11),
    ]

    c00 = A[0][0] * B[0][0] + A[0][1] * B[1][0]
    c01 = A[0][0] * B[0][1] + A[0][1] * B[1][1]
    c10 = A[1][0] * B[0][0] + A[1][1] * B[1][0]
    c11 = A[1][0] * B[0][1] + A[1][1] * B[1][1]

    expected = [
        relu_quant8(c00, shift),
        relu_quant8(c01, shift),
        relu_quant8(c10, shift),
        relu_quant8(c11, shift),
    ]

    cycles = (await read_reg(dut, REG_CYCLES_L)) | ((await read_reg(dut, REG_CYCLES_H)) << 8)

    assert result == expected, f"A={A}, B={B}, shift={shift}, expected={expected}, got={result}"
    assert cycles > 0, f"cycle counter expected > 0, got {cycles}"

    dut._log.info(f"A={A}, B={B}, shift={shift}, output={result}, cycles={cycles}")


@cocotb.test()
async def test_register_mapped_tensor_core(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())
    await reset(dut)

    await run_case(
        dut,
        A=[[1, 2], [3, 4]],
        B=[[5, 6], [7, 8]],
        shift=0,
    )

    await run_case(
        dut,
        A=[[4, -3], [-2, 5]],
        B=[[6, -1], [-7, 2]],
        shift=1,
    )

    random.seed(331)

    for _ in range(20):
        A = [
            [random.randint(-8, 8), random.randint(-8, 8)],
            [random.randint(-8, 8), random.randint(-8, 8)],
        ]
        B = [
            [random.randint(-8, 8), random.randint(-8, 8)],
            [random.randint(-8, 8), random.randint(-8, 8)],
        ]
        shift = random.randint(0, 3)

        await run_case(dut, A, B, shift)