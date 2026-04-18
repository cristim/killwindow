BIN        := killwindow
BUILD_DIR  := .build
REL_BIN    := $(BUILD_DIR)/release/$(BIN)
PREFIX     ?= /usr/local

.PHONY: all build run install uninstall clean lint fmt

all: build

build:
	swift build -c release

run: build
	$(REL_BIN)

install: build
	install -m 0755 $(REL_BIN) $(PREFIX)/bin/$(BIN)

uninstall:
	rm -f $(PREFIX)/bin/$(BIN)

clean:
	swift package clean
	rm -rf $(BUILD_DIR)

# Optional: requires swift-format installed (brew install swift-format)
fmt:
	swift-format format --in-place --recursive Sources

lint:
	swift-format lint --recursive Sources
