QUARTUS_CYCLONEIII =
QUARTUS_CYCLONEV =
QUARTUS_CYCLONE10LP =
QUARTUS_MAX10 = 

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
	for BOARD in ${BOARDS_CYCLONEIII}; do \
		make -C $$BOARD QUARTUS=$(QUARTUS_CYCLONEIII); \
	done
	for BOARD in ${BOARDS_CYCLONE10LP}; do \
		make -C $$BOARD QUARTUS=$(QUARTUS_CYCLONE10LP); \
	done
	for BOARD in ${BOARDS_MAX10}; do \
		make -C $$BOARD QUARTUS=$(QUARTUS_MAX10); \
	done
	for BOARD in ${BOARDS_CYCLONEV}; do \
		make -C $$BOARD QUARTUS=$(QUARTUS_CYCLONEV); \
	done

clean:
	for BOARD in ${BOARDS_CYCLONEIII}; do \
		make -C $$BOARD QUARTUS=$(QUARTUS_CYCLONEIII) clean ;\
	done
	for BOARD in ${BOARDS_CYCLONE10LP}; do \
		make -C $$BOARD QUARTUS=$(QUARTUS_CYCLONE10LP) clean ;\
	done
	for BOARD in ${BOARDS_MAX10}; do \
		make -C $$BOARD QUARTUS=$(QUARTUS_MAX10) clean ;\
	done
	for BOARD in ${BOARDS_CYCLONEV}; do \
		make -C $$BOARD QUARTUS=$(QUARTUS_CYCLONEV) clean ;\
	done

