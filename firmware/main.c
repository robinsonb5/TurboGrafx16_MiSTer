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
#include "osd.h"
#include "menu.h"

#include "printf.h"

#define Breadcrumb(x) HW_UART(REG_UART)=x;

#define UPLOADBASE 0xFFFFFFF8
#define UPLOAD_ENA 0
#define UPLOAD_DAT 4
#define HW_UPLOAD(x) *(volatile unsigned int *)(UPLOADBASE+x)

/* Upload data to FPGA */

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
			char *buf=sector_buffer;
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
			SPI_ENABLE(HW_SPI_FPGA|HW_SPI_FAST);
			SPI(SPI_FPGA_FILE_TX_DAT);
			while(sendsize--)
			{
				SPI(*buf++);
			}
			SPI_DISABLE(HW_SPI_FPGA);
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



static void reset(int row)
{
	Menu_Hide();
	// FIXME reset here
}


static void SaveSettings(int row)
{
	Menu_Hide();
	// FIXME reset here
}

static void MenuHide(int row)
{
	Menu_Hide();
}

static void showrommenu(int row)
{
}


static char *video_labels[]=
{
	"VGA - 31KHz, 60Hz",
	"TV - 480i, 60Hz"
};


static struct menu_entry topmenu[]=
{
	{MENU_ENTRY_CALLBACK,"Reset",MENU_ACTION(&reset)},
	{MENU_ENTRY_CALLBACK,"Save settings",MENU_ACTION(&SaveSettings)},
	{MENU_ENTRY_CYCLE,(char *)video_labels,2},
	{MENU_ENTRY_TOGGLE,"Scanlines",1},
//	{MENU_ENTRY_CYCLE,(char *)cart_labels,2},
	{MENU_ENTRY_CALLBACK,"Load ROM \x10",MENU_ACTION(&showrommenu)},
//	{MENU_ENTRY_CALLBACK,"Debug \x10",MENU_ACTION(&debugmode)},
	{MENU_ENTRY_CALLBACK,"Exit",MENU_ACTION(&MenuHide)},
	{MENU_ENTRY_NULL,0,0}
};





char filename[16];
//void setstack();
int main(int argc,char **argv)
{
	int havesd;
	int i,c;
	int osd=0;
//	setstack();

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

	Menu_Set(topmenu);

	EnableInterrupts();
	while(1)
	{
		HandlePS2RawCodes();

		if(Menu_Run())
		{
			

		}

		if(TestKey(KEY_F11))
		{
			if(havesd && SendFile(filename))
			{
				puts("ROM loaded\n");
			}
			else
				puts("ROM load failed\n");
		}
	}

	return(0);
}

