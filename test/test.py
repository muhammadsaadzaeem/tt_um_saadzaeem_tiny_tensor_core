import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CMD_LOAD = 0xA0
CMD_COMPUTE = 0xB0
CMD_READ = 0xC0
CMD_SHIFT = 0xD0


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


async def read_byte(dut):
    dut.ui_in.value = CMD_READ
    dut.uio_in.value = 1
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0
    dut.ui_in.value = 0
    await RisingEdge(dut.clk)
    return int(dut.uo_out.value)


def to_u8(x):
    return x & 0xFF


def relu_quant8(x, shift):
    y = max(0, x) >> shift
    return min(y, 127)


async def run_case(dut, A, B, shift):
    await send_byte(dut, CMD_SHIFT)
    await send_byte(dut, shift)

    await send_byte(dut, CMD_LOAD)

    values = [
        A[0][0], A[0][1], A[1][0], A[1][1],
        B[0][0], B[0][1], B[1][0], B[1][1],
    ]

    for value in values:
        await send_byte(dut, to_u8(value))

    await send_byte(dut, CMD_COMPUTE)
    await ClockCycles(dut.clk, 20)

    result = [await read_byte(dut) for _ in range(6)]

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

    cycles = result[4] | (result[5] << 8)

    assert result[0:4] == expected, (
        f"A={A}, B={B}, shift={shift}, expected={expected}, got={result[0:4]}"
    )
    assert cycles > 0, f"cycle counter expected > 0, got {cycles}"

    dut._log.info(f"A={A}, B={B}, shift={shift}, output={result[0:4]}, cycles={cycles}")


@cocotb.test()
async def test_randomized_requantized_matmul(dut):
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