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

int statusword; /* Support 32-bit status word initially - need to be 64-bit in the long run */
#define LINELENGTH 32
char exts[32];

#define conf_next() SPI(0xff)

int conf_nextfield()
{
	int c;
	do
		c=conf_next();
	while(c && c!=';');
	return(c);
}

/* Copy a maximum of limit bytes to the output string, stopping when a comma is reached. */
/* If the copy flag is zero, don't copy, just consume bytes from the input */

int copytocomma(char *buf, int limit,int copy)
{
	int count=0;
	int c;
	c=conf_next();
	while(c && c!=',' && c!=';')
	{
		if(count<limit && copy)
			*buf++=c;
		if(c)
			++count;
		c=conf_next();
	}
	if(copy)
		*buf++=0;
	return(c==';' ? -count : count);
}


int getdigit()
{
	int c=-1;
	c=conf_next();
	if(!c || c==',' || c==';')
		c=-1;
	else
	{
		if(c>'9')
			c=c+10-'A';
		else
			c-='0';
	}
	return(c);	
}

/* Upload data to FPGA */

fileTYPE file;

void VerifyROM()
{
	int imgsize=file.size;
	int sendsize;
	SPI_ENABLE(HW_SPI_FPGA)
	SPI(SPI_FPGA_FILE_TX);
	SPI(0x03);	/* Verify */
	SPI_DISABLE(HW_SPI_FPGA);

	SPI_ENABLE_FAST(HW_SPI_SNIFF);
	while(imgsize)
	{
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
		while(sendsize--)
		{
			SPI(0x00);
		}
		SPI(0x00); /* CRC bytes */
		SPI(0x00);
	}
	SPI_DISABLE(HW_SPI_SNIFF);

	SPI_ENABLE(HW_SPI_FPGA);
	SPI(SPI_FPGA_FILE_TX);
	SPI(0x00);
	SPI_DISABLE(HW_SPI_FPGA);
}

int LoadROM(const char *fn)
{
	if(FileOpen(&file,fn))
	{
		int imgsize=file.size;
		int sendsize;
		puts("Opened file, loading...\n");

		SPI_ENABLE(HW_SPI_FPGA);
		SPI(SPI_FPGA_FILE_TX);
		SPI(0x01); /* Upload */
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

		VerifyROM();
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

int romindex;
static void listroms();
static void selectrom(int row);
static void scrollroms(int row);
void buildmenu(int page,int offset);
static void submenu(int row);

static char romfilenames[7][30];

static struct menu_entry menu[]=
{
	{MENU_ENTRY_CALLBACK,0,0,0,romfilenames[0],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,0,0,0,romfilenames[1],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,0,0,0,romfilenames[2],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,0,0,0,romfilenames[3],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,0,0,0,romfilenames[4],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,0,0,0,romfilenames[5],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,0,0,0,romfilenames[6],MENU_ACTION(&selectrom)},
	{MENU_ENTRY_CALLBACK,0,0,0,"Back",MENU_ACTION(submenu)},
	{MENU_ENTRY_NULL,0,0,0,0,MENU_ACTION(scrollroms)}
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
	
	Menu_Set(menu);
	Menu_Hide();
}


static void selectdir(int row)
{
	DIRENTRY *p=nthfile(romindex+row);
	if(p)
		ChangeDirectory(p);
	romindex=0;
	listroms();
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
}


static void listroms(int row)
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
				menu[j].action=MENU_ACTION(&selectdir);
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
				menu[j].action=MENU_ACTION(&selectrom);
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
	Menu_Draw();
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
	Menu_Set(menu);
}


static void submenu(int row)
{
	int page=menu[row].val;
	puts("submenu callback");
	putchar(row+'0');
	buildmenu(page,0);
}

int parseconf(int selpage,struct menu_entry *menu,int first,int limit)
{
	int c;
	int maxpage=0;
	int line=0;
	char *title;

	SPI(0xff);
	SPI_ENABLE(HW_SPI_CONF);
	SPI(SPI_CONF_READ); // Read conf string command

	conf_nextfield(); /* Skip over core name */
	c=conf_nextfield(); /* Skip over core file extensions */
	while(c && line<limit)
	{
		c=conf_next();
		switch(c)
		{
			case 'F':
				{
					int i=0;
					c=conf_next(); /* Step over first comma */
					if(selpage==0)
					{
						while((exts[i++]=conf_next())!=',')
							;
						exts[i-1]=0;
						strcpy(menu[line].label,"Load");
						menu[line].action=MENU_ACTION(&listroms);
						++line;
					}
//					printf("File selector, extensions %s\n",exts);
					c=conf_nextfield();
				}
				break;
			case 'P':
				{
					int page;
					page=getdigit();

//					printf("Page %d\n",page);

					if(page>maxpage)
						maxpage=page;
					c=getdigit();

					if(c<0)
					{
						/* Is this a submenu declaration? */
						if(selpage==0)
						{
							title=menu[line].label;
							menu[line].val=page;
							menu[line].type=MENU_ENTRY_CALLBACK;
							menu[line].action=MENU_ACTION(&submenu);
							c=conf_next();
							while(c && c!=';')
							{
								*title++=c;
								c=conf_next();
							}
							*title++=' ';
							*title++='-';
							*title++='>';
							*title++=0;
							line++;
						}
						else
							c=conf_nextfield();
					}
					else if (page==selpage)
					{
						/* Must be a submenu entry */
						int low,high=0;
						int opt=0;
						int mask;

						/* Parse option */
						low=getdigit();
						high=getdigit();

						if(high<0)
							high=low;
						else
							conf_next();

						mask=(1<<(1+high-low))-1;
						menu[line].shift=low;
						menu[line].val=(statusword>>low)&mask;

						title=menu[line].label;
//						printf("selpage %d, page %d\n",selpage,page);
						if((c=copytocomma(title,LINELENGTH,selpage==page))>0)
						{
							if(c>0)
								title+=c;
							strncpy(title,": ",menu[line].label+LINELENGTH-title);
							title+=2;
							do
							{
								++opt;
							} while(copytocomma(title,menu[line].label+LINELENGTH-title,opt==menu[line].val+1)>0);
						}
//						printf("Decoded %d options\n",opt);
						menu[line].limit=opt;
						++line;
					}
					else
						c=conf_nextfield();
				}
				break;
			default:
				c=conf_nextfield();
				break;
		}
	}
	for(;line<8;++line)
	{
		*menu[line].label=0;
	}
	if(selpage)
	{
		strcpy(menu[7].label,"Back");
	}
//	printf("Maxpage %d\n",maxpage);
	SPI_DISABLE(HW_SPI_CONF);
	return(maxpage);
}


void buildmenu(int page,int offset)
{
	parseconf(page,menu,0,8);
	Menu_Set(menu);
}


char filename[16];
int main(int argc,char **argv)
{
	int havesd;
	int i,c;
	int osd=0;

	PS2Init();

	filename[0]=0;

	SPI(0xff);
	puts("Initializing SD card\n");
	if(havesd=spi_init() && FindDrive())
		puts("Have SD\n");

	buildmenu(0,0);

	EnableInterrupts();
	while(1)
	{
		HandlePS2RawCodes();

		if(Menu_Run())
		{
			

		}
		if(TestKey(KEY_F1))
		{
			VerifyROM();
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

