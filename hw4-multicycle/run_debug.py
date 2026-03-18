from pathlib import Path
from cocotb.runner import get_runner
import sys

p = Path.cwd() / '..' / 'common' / 'python'
sys.path.append(str(p))
import cocotb_utils as cu

PROJECT_PATH = Path(__file__).resolve().parent

verilog_sources = [PROJECT_PATH / "DatapathMultiCycle.sv"]
toplevel_module = "Processor"

runr = get_runner(cu.SIM)
runr.build(
    verilog_sources=verilog_sources,
    vhdl_sources=[],
    hdl_toplevel=toplevel_module,
    includes=[PROJECT_PATH],
    build_dir=cu.SIM_BUILD_DIR,
    waves=True,
    build_args=cu.VERILATOR_FLAGS + ['-DDIVIDER_STAGES=8'],
)

runr.test(
    seed=12345,
    waves=True,
    hdl_toplevel=toplevel_module,
    test_module='debug_trace',
)
