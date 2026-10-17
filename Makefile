PREFIX ?= /usr/local
CFLAGS ?= -O2 -Wall -Wextra

build/pluglight: src/pluglight.c
	@mkdir -p build
	$(CC) $(CFLAGS) -framework IOKit -o $@ $<

test: build/pluglight
	sh tests/run.sh

clean:
	rm -rf build

.PHONY: test clean

app:
	sh app/build.sh

install-app: app
	rm -rf "/Applications/PlugLight.app"
	cp -R "build/PlugLight.app" /Applications/
	open "/Applications/PlugLight.app"

.PHONY: app install-app
