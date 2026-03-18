import cocotb
import json
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
async def debugTraceCompare(dut):
    "Debug trace comparison with 35+ instructions before div"
    asm = '''
        addi x1, x0, 0
        addi x2, x0, 0
        addi x3, x0, 0
        addi x4, x0, 0
        addi x5, x0, 0
        addi x6, x0, 0
        addi x7, x0, 0
        addi x8, x0, 0
        addi x9, x0, 0
        addi x10, x0, 0
        addi x11, x0, 0
        addi x12, x0, 0
        addi x13, x0, 0
        addi x14, x0, 0
        addi x15, x0, 0
        addi x16, x0, 0
        addi x17, x0, 0
        addi x18, x0, 0
        addi x19, x0, 0
        addi x20, x0, 0
        addi x21, x0, 0
        addi x22, x0, 0
        addi x23, x0, 0
        addi x24, x0, 0
        addi x25, x0, 0
        addi x26, x0, 0
        addi x27, x0, 0
        addi x28, x0, 0
        addi x29, x0, 0
        addi x30, x0, 0
        addi x31, x0, 0
        addi x3, x0, 0
        addi x3, x0, 2
        addi x1, x0, 20
        addi x2, x0, 6
        div x14, x1, x2
        addi x3, x0, 3
        ecall'''
    await preTestSetup(dut, asm)

    with open('../trace-rv32um-p-div.json', 'r') as f:
        trace = json.load(f)

    for cycles in range(50):
        await RisingEdge(dut.clock_proc)
        pc = dut.datapath.trace_completed_pc.value.integer
        insn = dut.datapath.trace_completed_insn.value.integer
        status = dut.datapath.trace_completed_cycle_status.value.integer
        div_count = dut.datapath.div_cycle_count.value.integer
        div_stall_val = dut.datapath.div_stall.value.integer

        if cycles < len(trace):
            expected_pc = int(trace[cycles]['trace_completed_pc'], 16)
            expected_status = trace[cycles]['trace_completed_cycle_status']
            match_pc = "OK" if pc == expected_pc else f"MISMATCH(exp=0x{expected_pc:x})"
            dut._log.info(f'cycle={cycles}: pc=0x{pc:x} {match_pc} insn=0x{insn:08x} status={status} div_cnt={div_count} stall={div_stall_val} exp_status={expected_status}')
        else:
            dut._log.info(f'cycle={cycles}: pc=0x{pc:x} insn=0x{insn:08x} status={status} div_cnt={div_count} stall={div_stall_val}')

        if dut.halt.value == 1:
            dut._log.info(f'HALT at cycle {cycles}')
            break
