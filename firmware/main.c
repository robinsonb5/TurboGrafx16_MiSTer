/*	Firmware for loading files from SD card.
	SPI and FAT code borrowed from the Minimig project.
*/


#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "uart.h"
#include "spi.h"
#include "minfat.h"
#include "interrupts.h"
#include "keyboard.h"
#include "ps2.h"
#include "userio.h"
#include "osd.h"
#include "menu.h"
#include "font.h"

#define Breadcrumb(x) HW_UART(REG_UART)=x;

#define UPLOADBASE 0xFFFFFFF8
#define UPLOAD_ENA 0
#define UPLOAD_DAT 4
#define HW_UPLOAD(x) *(volatile unsigned int *)(UPLOADBASE+x)

/* Upload data to FPGA */

fileTYPE file;

int LoadROM(const char *fn)
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
			if(!FileRead(&file,0))//sector_buffer))
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
/*
			SPI_ENABLE(HW_SPI_FPGA|HW_SPI_FAST);
			SPI(SPI_FPGA_FILE_TX_DAT);
			while(sendsize--)
			{
				SPI(*buf++);
			}
			SPI_DISABLE(HW_SPI_FPGA);
*/
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

static struct menu_entry topmenu[];

int romindex;
static void listroms();
static void selectrom(int row);
static void scrollroms(int row);

static char romfilenames[7][30];

static struct menu_entry rommenu[]=
{
	{MENU_ENTRY_CALLBACK,romfilenames[0],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,romfilenames[1],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,romfilenames[2],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,romfilenames[3],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,romfilenames[4],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,romfilenames[5],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,romfilenames[6],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_SUBMENU,"Back",MENU_ACTION(topmenu)},
	{MENU_ENTRY_NULL,0,MENU_ACTION(scrollroms)}
};


static DIRENTRY *nthfile(int n)
{
	int i,j=0;
	DIRENTRY *p;
	for(i=0;(j<=n) && (i<dir_entries);++i)
	{
		p=NextDirEntry(i);
		if(p)
			++j;
	}
	return(p);
}


static void selectrom(int row)
{
	DIRENTRY *p=nthfile(romindex+row);
	if(p)
	{
		strncpy(longfilename,p->Name,11); // Make use of the long filename buffer to store a temporary copy of the filename,
		LoadROM(longfilename);	// since loading it by name will overwrite the sector buffer which currently contains it!
	}
	Menu_Set(topmenu);
	Menu_Hide();
}


static void selectdir(int row)
{
	DIRENTRY *p=nthfile(romindex+row);
	if(p)
		ChangeDirectory(p);
	romindex=0;
	listroms();
	Menu_Draw();
}


static void scrollroms(int row)
{
	switch(row)
	{
		case ROW_LINEUP:
			if(romindex)
				--romindex;
			break;
		case ROW_PAGEUP:
			romindex-=16;
			if(romindex<0)
				romindex=0;
			break;
		case ROW_LINEDOWN:
			++romindex;
			break;
		case ROW_PAGEDOWN:
			romindex+=16;
			break;
	}
	listroms();
	Menu_Draw();
}


static void listroms()
{
	int i,j;
	j=0;
	printf("listrom skipping %d, direntries %d \n",romindex,dir_entries);
	for(i=0;(j<romindex) && (i<dir_entries);++i)
	{
		DIRENTRY *p=NextDirEntry(i);
		if(p)
			++j;
	}

	for(j=0;(j<7) && (i<dir_entries);++i)
	{
		DIRENTRY *p=NextDirEntry(i);
		if(p)
		{
			// FIXME declare a global long file name buffer.
			if(p->Attributes&ATTR_DIRECTORY)
			{
				printf("Found directory\n");
				rommenu[j].action=MENU_ACTION(&selectdir);
				romfilenames[j][0]=FONT_ARROW_RIGHT; // Right arrow
				romfilenames[j][1]=' ';
				if(longfilename[0])
					strncpy(romfilenames[j++]+2,longfilename,28);
				else
					strncpy(romfilenames[j++]+2,p->Name,11);
			}
			else
			{
				printf("Found file\n");
				rommenu[j].action=MENU_ACTION(&selectrom);
				if(longfilename[0])
					strncpy(romfilenames[j++],longfilename,28);
				else
					strncpy(romfilenames[j++],p->Name,11);
			}
		}
		else
			romfilenames[j][0]=0;
	}
	for(;j<7;++j)
		romfilenames[j][0]=0;
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
	romindex=0;
	listroms();
	Menu_Set(rommenu);
//	Menu_SetHotKeys(hotkeys);
}


static char *video_labels[]=
{
	"VGA - 31KHz, 60Hz",
	"TV - 480i, 60Hz"
};


static char *scanline_labels[]=
{
	"Scanlines: Off",
	"Scanlines: 25%",
	"Scanlines: 50%",
	"Scanlines: 75%"
};


static struct menu_entry topmenu[]=
{
	{MENU_ENTRY_CALLBACK,"Reset",MENU_ACTION(&reset)},
	{MENU_ENTRY_CALLBACK,"Save settings",MENU_ACTION(&SaveSettings)},
	{MENU_ENTRY_CYCLE,(char *)video_labels,2},
	{MENU_ENTRY_CYCLE,(char *)scanline_labels,4},
	{MENU_ENTRY_TOGGLE,"Video filter",0},
//	{MENU_ENTRY_CYCLE,(char *)cart_labels,2},
	{MENU_ENTRY_CALLBACK,"Load ROM \x81",MENU_ACTION(&showrommenu)},
//	{MENU_ENTRY_CALLBACK,"Debug \x10",MENU_ACTION(&debugmode)},
	{MENU_ENTRY_CALLBACK,"Exit",MENU_ACTION(&MenuHide)},
	{MENU_ENTRY_NULL,0,0}
};


char filename[16];
int main(int argc,char **argv)
{
	int havesd;
	int i,c;
	int osd=0;

	PS2Init();

	filename[0]=0;

	SPI(0xff);
	SPI_ENABLE(HW_SPI_CONF);
	SPI(SPI_CONF_READ); // Read conf string command
	i=0;
	while(c=SPI(0xff))
	{
		filename[i]=c;
//		spin();
		putchar(c);

#if 0
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
#endif
	}
	while(c=SPI(0xff))
		;
	SPI_DISABLE(HW_SPI_CONF);

//	spin();
//	puts(filename);

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
			if(havesd && LoadROM(filename))
			{
				puts("ROM loaded\n");
			}
			else
				puts("ROM load failed\n");
		}
	}

	return(0);
}

