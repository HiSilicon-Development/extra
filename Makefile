CC ?= cc
CPPFLAGS ?=
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Wpedantic
LDFLAGS ?=
LDLIBS ?=

.PHONY: all clean

all: payload/bin/hivxe-top

payload/bin/hivxe-top: src/hivxe-top.c
	mkdir -p $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $< $(LDLIBS)

clean:
	$(RM) payload/bin/hivxe-top
