
all: $(PROJECT)_$(BOARD).qsf $(PROJECT)_$(BOARD).rbf

%.qsf: %.tcl
	$(QUARTUS)/quartus_sh -t ../tcl/mkproject.tcl -project $(PROJECT) -board $(BOARD)

%.rbf: %.qsf
	$(QUARTUS)/quartus_sh -t ../tcl/compile.tcl -project $(PROJECT) -board $(BOARD)

