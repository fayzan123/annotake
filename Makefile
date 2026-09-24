.DEFAULT_GOAL := app
KC := $(CURDIR)/.signing/flipbook-signing.keychain-db
BIN = $(shell swift build -c release --show-bin-path)
.PHONY: app run install zip selftest ui-snapshots cert clean
app:
	swift build -c release --product Flipbook
	scripts/bundle-app.sh $(BIN)/Flipbook Flipbook com.fayzanmalik.flipbook build
run: app
	open build/Flipbook.app
install: app
	rm -rf ~/Applications/Flipbook.app && ditto build/Flipbook.app ~/Applications/Flipbook.app
zip: app
	cd build && rm -f Flipbook.zip && ditto -c -k --keepParent Flipbook.app Flipbook.zip
selftest: app
	rm -rf build/selftest && mkdir -p build/selftest
	caffeinate -u -t 2 || true
	open -W -n build/Flipbook.app --args --selftest "$(CURDIR)/build/selftest"
	cat build/selftest/selftest.txt
	grep -q '^PASSED' build/selftest/selftest.txt
ui-snapshots: app
	rm -rf build/ui && mkdir -p build/ui
	open -W -n build/Flipbook.app --args --render-ui "$(CURDIR)/build/ui"
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
	swift run flipbook-replay "$(SESSION)"
