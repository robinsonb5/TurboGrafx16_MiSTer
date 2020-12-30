/*	Firmware for loading files from SD card.
	SPI and FAT code borrowed from the Minimig project.
*/


#include "stdarg.h"

#include "uart.h"
#include "spi.h"
#include "minfat.h"
#include "interrupts.h"
#include "keyboard.h"
#include "ps2.h"
#include "userio.h"

#include "printf.h"

#define Breadcrumb(x) HW_UART(REG_UART)=x;

#define UPLOADBASE 0xFFFFFFF8
#define UPLOAD_ENA 0
#define UPLOAD_DAT 4
#define HW_UPLOAD(x) *(volatile unsigned int *)(UPLOADBASE+x)

/* Upload data to FPGA */

void SendBlock(const char *buf,int size)
{
	SPI_ENABLE(HW_SPI_FPGA|HW_SPI_FAST);
	SPI(SPI_FPGA_FILE_TX_DAT);
	while(size--)
	{
		SPI(*buf++);
	}
	SPI_DISABLE(HW_SPI_FPGA);
}

fileTYPE file;

int SendFile(const char *fn)
{
	if(FileOpen(&file,fn))
	{
		int imgsize=file.size;
		int sendsize;
		puts("Opened file, loading...\n");

		SPI_ENABLE(HW_SPI_FPGA);
		SPI(SPI_FPGA_FILE_TX);
		SPI(0xff);
		SPI_DISABLE(HW_SPI_FPGA);

		while(imgsize)
		{
			if(!FileRead(&file,sector_buffer))
				return(0);

			if(imgsize>=512)
			{
				sendsize=512;
				imgsize-=512;
			}
			else
			{
				sendsize=imgsize;
				imgsize=0;
			}
			SendBlock(sector_buffer,sendsize);
			FileNextSector(&file);
		}
		SPI_ENABLE(HW_SPI_FPGA);
		SPI(SPI_FPGA_FILE_TX);
		SPI(0x00);
		SPI_DISABLE(HW_SPI_FPGA);
	}
	else
	{
		printf("Can't open %s\n",fn);
		return(0);
	}
	return(1);
}


void spin()
{
	int i,t;
	for(i=0;i<1024;++i)
		t=HW_SPI(HW_SPI_CS);
}

char filename[16];
void setstack();
int main(int argc,char **argv)
{
	int havesd;
	int i,c;
	setstack();

	PS2Init();

	puts("Fetching conf string\n");
	filename[0]=0;

	SPI(0xff);
	SPI_ENABLE(HW_SPI_CONF);
	SPI(SPI_CONF_READ); // Read conf string command
	i=0;
	while(c=SPI(0xff))
	{
		filename[i]=c;
		spin();
		putchar(c);
		if(c==';')
		{
			if(i<8)
			{
				for(;i<8;++i)
					filename[i]=' ';
			}
			else if(i>8)
			{
				filename[6]='~';
				filename[7]='1';
			}
			filename[8]='R';
			filename[9]='O';
			filename[10]='M';
			filename[11]=0;
			break;
		}
		++i;
	}
	while(c=SPI(0xff))
		;
	SPI_DISABLE(HW_SPI_CONF);

	spin();
	puts(filename);

	puts("Initializing SD card\n");
	havesd=spi_init() && FindDrive();
	printf("Have SD? %d\n",havesd);

	EnableInterrupts();
	while(1)
	{
		int joy0=0;
		int joy1=0;
		HandlePS2RawCodes();

		if(TestKey(KEY_F12))
		{
			if(havesd && SendFile(filename))
			{
				puts("ROM loaded\n");
			}
			else
				puts("ROM load failed\n");
		}

		if(TestKey(KEY_UPARROW))
			joy0=JOY_UP;
		if(TestKey(KEY_DOWNARROW))
			joy0|=JOY_DOWN;
		if(TestKey(KEY_LEFTARROW))
			joy0|=JOY_LEFT;
		if(TestKey(KEY_RIGHTARROW))
			joy0|=JOY_RIGHT;
		if(TestKey(KEY_RCTRL))
			joy0|=JOY_BTN1;
		if(TestKey(KEY_RSHIFT))
			joy0|=JOY_BTN2;
		if(TestKey(KEY_ALTGR))
			joy0|=JOY_BTN3;
		if(TestKey(KEY_ENTER))
			joy0|=JOY_BTN4;

		user_io_digital_joystick_ext(0, joy0);

	}

	return(0);
}

