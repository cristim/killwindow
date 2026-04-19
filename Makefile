BIN        := killwindow
BUILD_DIR  := .build
REL_BIN    := $(BUILD_DIR)/release/$(BIN)
APP_OUT    := build
APP        := $(APP_OUT)/$(BIN).app
PREFIX     ?= /usr/local

.PHONY: all build app run install uninstall clean lint fmt

all: app

build:
	swift build -c release

app: build
	bash scripts/build-app.sh $(APP_OUT)

run: build
	$(REL_BIN)

install: app
	install -d "$(PREFIX)/opt/killwindow"
	rm -rf "$(PREFIX)/opt/killwindow/$(BIN).app"
	cp -R $(APP) "$(PREFIX)/opt/killwindow/"
	ln -sf "$(PREFIX)/opt/killwindow/$(BIN).app/Contents/MacOS/$(BIN)" \
	       "$(PREFIX)/bin/$(BIN)"

uninstall:
	rm -f  "$(PREFIX)/bin/$(BIN)"
	rm -rf "$(PREFIX)/opt/killwindow"

clean:
	swift package clean
	rm -rf $(BUILD_DIR) $(APP_OUT)

# Optional: requires swift-format installed (brew install swift-format)
fmt:
	swift-format format --in-place --recursive Sources

lint:
	swift-format lint --recursive Sources
