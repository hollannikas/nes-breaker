PROJECT = game

AS = ca65
LD = ld65

SRCS = main.asm
OBJS = $(SRCS:.asm=.o)
CFG = nes.cfg

.PHONY: all clean

all: $(PROJECT).nes

$(PROJECT).nes: $(OBJS) $(CFG)
	$(LD) -C $(CFG) -o $@ $(OBJS)

%.o: %.asm
	$(AS) -g -o $@ $<

clean:
	rm -f $(OBJS) $(PROJECT).nes
