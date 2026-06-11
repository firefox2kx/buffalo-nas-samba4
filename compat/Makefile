CC      = arm-linux-gnueabi-gcc
CFLAGS  = -march=armv5te -mfloat-abi=soft -Os -D_FORTIFY_SOURCE=0
AR      = arm-linux-gnueabi-ar

all: libisoc99_compat.a

libisoc99_compat.a: isoc99_compat.o resolv_compat.o
	$(AR) rcs $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f *.o libisoc99_compat.a
