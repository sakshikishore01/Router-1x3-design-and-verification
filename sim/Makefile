# ==============================================================================
# Cadence Incisive (NC-Sim) Self-Contained Makefile
# ==============================================================================

# Force the Makefile to execute rules using standard Bash shell
SHELL := /bin/bash

VLOG      = ncvlog
ELAB      = ncelab
SIM       = ncsim

# CRITICAL: Added '-work worklib' so ncvlog knows exactly where to store files without relying on external config files
VLOG_FLAGS = -messages -sv -linedebug -work worklib
ELAB_FLAGS  = -messages -access +rwc -timescale 1ns/1ps
SIM_FLAGS   = -messages -input ncsim.key

DUT_SRCS   = router_sync.sv router_fifo.sv router_fsm.sv router_reg.sv router_top.sv
TB_TOP     = tb_top.sv

all: clean compile elab sim

# 1. Compile Phase with Robust Auto-Initialization
compile:
	@echo "========================================================="
	@echo "[MAKE] Forcing Library Sandbox Creation..."
	@echo "========================================================="
	mkdir -p INCA_libs/worklib
	@rm -f cds.lib hdl.var
	@echo "DEFINE worklib ./INCA_libs/worklib" > cds.lib
	@echo "DEFINE WORK worklib" > hdl.var
	@echo "========================================================="
	@echo "[MAKE] Compiling Hardware DUT Core Files..."
	@echo "========================================================="
	$(VLOG) $(VLOG_FLAGS) $(DUT_SRCS)
	@echo "========================================================="
	@echo "[MAKE] Compiling Testbench Infrastructure Wrapper..."
	@echo "========================================================="
	$(VLOG) $(VLOG_FLAGS) $(TB_TOP)

# 2. Elaboration Phase
elab:
	@echo "========================================================="
	@echo "[MAKE] Elaborating Design Snapshot (tb_top)..."
	@echo "========================================================="
	$(ELAB) $(ELAB_FLAGS) worklib.tb_top

# 3. Simulation Phase
sim:
	@echo "========================================================="
	@echo "[MAKE] Launching NC-Sim Functional Verification..."
	@echo "========================================================="
	$(SIM) $(SIM_FLAGS) worklib.tb_top

# 4. Waveform GUI Viewer Phase
waves:
	$(SIM) -gui worklib.tb_top:sv &

# 5. Directory Cleanup Phase
clean:
	@echo "========================================================="
	@echo "[MAKE] Cleaning Up Directory Artifacts..."
	@echo "========================================================="
	rm -rf INCA_libs waves.shm ncsim.shm INCA_libs
	rm -f *.log *.key *.vcd
	rm -f cds.lib hdl.var
