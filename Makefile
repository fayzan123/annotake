.DEFAULT_GOAL := app
KC := $(CURDIR)/.signing/annotake-signing.keychain-db
BIN = $(shell swift build -c release --show-bin-path)
# The marketing version, and the build number: the commit count.
VERSION := $(shell cat VERSION)
BUILD := $(shell git rev-list --count HEAD)
RELEASE ?= 0
.PHONY: app run install zip selftest ui-snapshots cert clean
app:
	swift build -c release --product Annotake
	RELEASE=$(RELEASE) VERSION=$(VERSION) BUILD=$(BUILD) \
		scripts/bundle-app.sh $(BIN)/Annotake Annotake com.fayzanmalik.annotake build
run: app
	open build/Annotake.app
install: app
	rm -rf /Applications/Annotake.app ~/Applications/Annotake.app && ditto build/Annotake.app /Applications/Annotake.app
zip: app
	cd build && rm -f Annotake.zip && ditto -c -k --keepParent Annotake.app Annotake.zip
selftest: app
	rm -rf build/selftest && mkdir -p build/selftest
	caffeinate -u -t 2 || true
	open -W -n build/Annotake.app --args --selftest "$(CURDIR)/build/selftest"
	cat build/selftest/selftest.txt
	grep -q '^PASSED' build/selftest/selftest.txt
ui-snapshots: app
	rm -rf build/ui && mkdir -p build/ui
	open -W -n build/Annotake.app --args --render-ui "$(CURDIR)/build/ui"
	ls build/ui
cert:
	scripts/make-cert.sh
clean:
	rm -rf .build build
CLT_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
# The CLT's _Testing_Foundation overlay has no module interface, so a test file importing both
# Testing and Foundation fails to compile unless cross-import overlays are turned off.
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_FW) -Xlinker -F -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW) \
	-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
.PHONY: test
test:
	swift test $(TEST_FLAGS) $(if $(FILTER),--filter '$(FILTER)')
.PHONY: replay
replay:
	swift run annotake-replay "$(SESSION)"
