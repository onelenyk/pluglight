PREFIX ?= /usr/local
CFLAGS ?= -O2 -Wall -Wextra

build/magsafe-light: src/magsafe-light.c
	@mkdir -p build
	$(CC) $(CFLAGS) -framework IOKit -o $@ $<

test: build/magsafe-light
	sh tests/run.sh

clean:
	rm -rf build

.PHONY: test clean
