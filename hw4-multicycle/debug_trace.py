import cocotb
import sys
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer
from cocotb.binary import BinaryValue

p = Path.cwd() / '..' / 'common' / 'python'
sys.path.append(str(p))
import riscv_binary_utils
from cocotb_utils import assertEquals

async def memClock(dut):
    high_time = Timer(2, units="ns")
    low_time = Timer(2, units="ns")
    await Timer(1, units="ns")
    while True:
        dut.clock_mem.value = 1
        await high_time
        dut.clock_mem.value = 0
        await low_time

async def preTestSetup(dut, insns):
    proc_clock = Clock(dut.clock_proc, 4, units="ns")
    cocotb.start_soon(proc_clock.start(start_high=True))
    cocotb.start_soon(memClock(dut))
    await RisingEdge(dut.clock_proc)
    dut.rst.value = 1
    await ClockCycles(dut.clock_proc, 1)
    riscv_binary_utils.asm(dut, insns)
    await ClockCycles(dut.clock_proc, 1)
    dut.rst.value = 0
    caller_name_binary = ''.join(format(ord(char), '08b') for char in 'debug'.ljust(32))
    dut.test_case.value = BinaryValue(caller_name_binary, n_bits=len(caller_name_binary))

@cocotb.test()
async def debugTrace(dut):
    "Debug trace signals during div"
    await preTestSetup(dut, '''
        addi x1, x0, 20
        addi x2, x0, 6
        div x3, x1, x2
        addi x4, x3, 1
        ecall''')

    for cycles in range(25):
        await RisingEdge(dut.clock_proc)
        pc = dut.datapath.trace_completed_pc.value.integer
        insn = dut.datapath.trace_completed_insn.value.integer
        status = dut.datapath.trace_completed_cycle_status.value.integer
        pc_current = dut.datapath.pcCurrent.value.integer
        div_count = dut.datapath.div_cycle_count.value.integer
        is_div = dut.datapath.is_divide.value.integer
        div_stall_val = dut.datapath.div_stall.value.integer
        dut._log.info(f'cycle={cycles}: trace_pc=0x{pc:x} pcCurrent=0x{pc_current:x} insn=0x{insn:08x} status={status} div_count={div_count} is_div={is_div} div_stall={div_stall_val}')
        if dut.halt.value == 1:
            dut._log.info(f'HALT at cycle {cycles}')
            break
