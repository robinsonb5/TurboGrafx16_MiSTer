832DIR=../EightThirtyTwo/
CC=$(832DIR)/vbcc/bin/vbcc832
AS=$(832DIR)/832a/832a
LD=$(832DIR)/832a/832l
DUMP=objdump
INCDIR=$(832DIR)/include/
LIBDIR=$(832DIR)/lib832

CFLAGS = -+ -O=1311 -size -unsigned-char
ASFLAGS = -el
LDFLAGS  = -el -s_STACKSIZE=0x300

START = $(LIBDIR)/crt0.a
LIBS = $(LIBDIR)/libtiny832.a

PRJ_OBJ = uart.o tiny_printf.o spi_sd.o minfat.o swap.o main.o interrupts.o ps2.o keyboard.o userio.o osd.o font.o menu.o

ROMGENDIR = ../EightThirtyTwo/romgen
ROMGEN = $(ROMGENDIR)/romgen

all: controller_rom.vhd

clean :
	-rm *.asm
	-rm *.S
	-rm *.o
	-rm *.vhd
	-rm *.bin
	-rm *.elf

%_rom.vhd: %.bin $(ROMGEN)
	sed 's/dualportram/$*_rom/' >$*_rom.vhd <$(ROMGENDIR)/rom_prologue.vhd
	$(ROMGEN) -b $*.bin >>$*_rom.vhd
	cat >>$*_rom.vhd $(ROMGENDIR)/rom_epilogue.vhd
	grep __bss_ $*.map

controller.bin : $(START) $(LIBS) $(PRJ_OBJ)
	$(LD) $(LDFLAGS) -o $@ -M controller.map $+

%.o : %.c Makefile
	$(CC) $(COPT) $(CFLAGS) -I$(INCDIR) -I$(LIBDIR) $*.c
	$(AS) $(ASFLAGS) -o $*.o $*.asm

%.o : $(LIBDIR)/%.asm Makefile 
	$(AS) $(ASFLAGS) -o $*.o $(LIBDIR)/$*.asm

%.asm : %.c Makefile
	$(CC) $(COPT) $(CFLAGS) -I$(INCDIR) -I$(LIBDIR) $*.c

$(ROMGEN): $(ROMGENDIR)/romgen.c
	gcc -o $(ROMGENDIR)/romgen $(ROMGENDIR)/romgen.c

force:

