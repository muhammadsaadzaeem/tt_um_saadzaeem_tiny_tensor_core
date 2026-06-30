import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

CMD_LOAD = 0xA0
CMD_COMPUTE = 0xB0
CMD_READ = 0xC0

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

@cocotb.test()
async def test_matrix_multiply(dut):
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())

    await reset(dut)

    await send_byte(dut, CMD_LOAD)

    for value in [1, 2, 3, 4, 5, 6, 7, 8]:
        await send_byte(dut, value)

    await send_byte(dut, CMD_COMPUTE)

    await ClockCycles(dut.clk, 20)

    result_bytes = []
    for _ in range(16):
        result_bytes.append(await read_byte(dut))

    def le32(bytes4):
        value = bytes4[0] | (bytes4[1] << 8) | (bytes4[2] << 16) | (bytes4[3] << 24)
        if value & 0x80000000:
            value -= 0x100000000
        return value

    c00 = le32(result_bytes[0:4])
    c01 = le32(result_bytes[4:8])
    c10 = le32(result_bytes[8:12])
    c11 = le32(result_bytes[12:16])

    assert c00 == 19, f"c00 expected 19, got {c00}"
    assert c01 == 22, f"c01 expected 22, got {c01}"
    assert c10 == 43, f"c10 expected 43, got {c10}"
    assert c11 == 50, f"c11 expected 50, got {c11}"