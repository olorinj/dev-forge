CC ?= gcc
CFLAGS ?= -O2 -Wall
LDFLAGS ?= -lcrypto

all: hashforge-c

hashforge-c: main.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -f hashforge-c *.o

