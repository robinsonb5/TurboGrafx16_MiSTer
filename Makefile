PROJECT = TurboGrafx16

Q13 = $(HOME)/altera/13.0sp1/quartus/bin/
Q18 = $(HOME)/intelFPGA_lite/18.1/quartus/bin/

QUARTUS_CYCLONEIII = $(Q13)
QUARTUS_CYCLONEV = $(Q18)
QUARTUS_CYCLONE10LP = $(Q18)
QUARTUS_MAX10 = $(Q18)

BOARDS_CYCLONEIII = chameleonv1 mist
BOARDS_CYCLONE10LP = chameleonv2
BOARDS_CYCLONEV = mister
BOARDS_MAX10 = de10lite

all: boards

EightThirtyTwo/RTL/eightthirtytwo_cpu.vhd:
	git submodule init
	git submodule update

EightThirtyTwo/vbcc/bin/vbcc832: EightThirtyTwo/RTL/eightthirtytwo_cpu.vhd
	make -C EightThirtyTwo

firmware: EightThirtyTwo/vbcc/bin/vbcc832 firmware/

boards:
	for BOARD in ${BOARDS_CYCLONE10LP}; do \
		make -C $$BOARD -f ../quartus.mk BOARD=$$BOARD PROJECT=$(PROJECT) QUARTUS=$(QUARTUS_CYCLONE10LP); \
	done
	for BOARD in ${BOARDS_CYCLONEIII}; do \
		make -C $$BOARD -f ../quartus.mk BOARD=$$BOARD PROJECT=$(PROJECT) QUARTUS=$(QUARTUS_CYCLONEIII); \
	done
	for BOARD in ${BOARDS_MAX10}; do \
		make -C $$BOARD -f ../quartus.mk BOARD=$$BOARD PROJECT=$(PROJECT) QUARTUS=$(QUARTUS_MAX10); \
	done
	for BOARD in ${BOARDS_CYCLONEV}; do \
		make -C $$BOARD -f ../quartus.mk BOARD=$$BOARD PROJECT=$(PROJECT) QUARTUS=$(QUARTUS_CYCLONEV); \
	done

clean:
	for BOARD in ${BOARDS_CYCLONEIII}; do \
		make -C $$BOARD PROJECT=$(PROJECT) QUARTUS=$(QUARTUS_CYCLONEIII) clean ;\
	done
	for BOARD in ${BOARDS_CYCLONE10LP}; do \
		make -C $$BOARD PROJECT=$(PROJECT) QUARTUS=$(QUARTUS_CYCLONE10LP) clean ;\
	done
	for BOARD in ${BOARDS_MAX10}; do \
		make -C $$BOARD PROJECT=$(PROJECT) QUARTUS=$(QUARTUS_MAX10) clean ;\
	done
	for BOARD in ${BOARDS_CYCLONEV}; do \
		make -C $$BOARD PROJECT=$(PROJECT) QUARTUS=$(QUARTUS_CYCLONEV) clean ;\
	done

