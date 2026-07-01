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
    dut.ui_in.value = value
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

def relu_quant8(x, shift):
    y = max(0, x) >> shift
    if y > 127:
        y = 127
    return y

@cocotb.test()
async def test_matrix_multiply_requantized(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())

    await reset(dut)

    shift = 0

    await send_byte(dut, CMD_SHIFT)
    await send_byte(dut, shift)

    await send_byte(dut, CMD_LOAD)

    A = [[1, 2], [3, 4]]
    B = [[5, 6], [7, 8]]

    for value in [1, 2, 3, 4, 5, 6, 7, 8]:
        await send_byte(dut, value)

    await send_byte(dut, CMD_COMPUTE)
    await ClockCycles(dut.clk, 20)

    result_bytes = []
    for _ in range(6):
        result_bytes.append(await read_byte(dut))

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

    cycles = result_bytes[4] | (result_bytes[5] << 8)

    assert result_bytes[0:4] == expected, f"expected {expected}, got {result_bytes[0:4]}"
    assert cycles > 0, f"cycle counter expected > 0, got {cycles}"

    dut._log.info(f"Quantized output: {result_bytes[0:4]}")
    dut._log.info(f"Measured accelerator latency: {cycles} cycles")