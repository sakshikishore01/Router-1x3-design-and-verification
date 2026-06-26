# ==============================================================================
# Cadence Incisive (NC-Sim / Xcelium) Integrated Verification Makefile
# ==============================================================================

SHELL := /bin/bash 

VLOG      = ncvlog 
ELAB      = ncelab 
SIM       = ncsim 

# Compilation Flags 
VLOG_FLAGS = -messages -sv -linedebug -work worklib 

# CRITICAL CHANGE: Added '-coverage functional' flag to instrument functional coverage 
ELAB_FLAGS  = -messages -access +rwc -timescale 1ns/1ps -coverage functional 

# CRITICAL CHANGE: Added '-covoverwrite' so each regression suite replaces out-of-date database logs 
SIM_FLAGS   = -messages -input ncsim.key -covoverwrite 

# Added coverage component directly into your Core DUT Sources array 
DUT_SRCS   = router_sync.sv router_fifo.sv router_fsm.sv router_reg.sv router_top.sv router_cov.sv 
TB_TOP     = tb_top.sv 

all: clean compile elab sim 

compile: 
	mkdir -p INCA_libs/worklib [cite: 370]
	@rm -f cds.lib hdl.var [cite: 370]
	@echo "DEFINE worklib ./INCA_libs/worklib" > cds.lib [cite: 370]
	@echo "DEFINE WORK worklib" > hdl.var [cite: 370]
	$(VLOG) $(VLOG_FLAGS) $(DUT_SRCS) [cite: 370]
	$(VLOG) $(VLOG_FLAGS) $(TB_TOP) [cite: 370]

elab: [cite: 370]
	$(ELAB) $(ELAB_FLAGS) worklib.tb_top [cite: 370]

sim: [cite: 370]
	$(SIM) $(SIM_FLAGS) worklib.tb_top [cite: 370]

waves: [cite: 370]
	$(SIM) -gui worklib.tb_top:sv & [cite: 370]

clean: [cite: 370]
	rm -rf INCA_libs waves.shm ncsim.shm cov_work *.ccv [cite: 370]
	rm -f *.log *.key *.vcd cds.lib hdl.var [cite: 370]
