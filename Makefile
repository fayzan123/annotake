.DEFAULT_GOAL := app
KC := $(CURDIR)/.signing/annotake-signing.keychain-db
# One app for both architectures: two release builds merged with lipo. Two --arch flags would need
# Xcode's XCBuild, which the Command Line Tools don't have.
ARM_TRIPLE := arm64-apple-macosx15.0
X86_TRIPLE := x86_64-apple-macosx15.0
ARM_BIN = $(shell swift build -c release --triple $(ARM_TRIPLE) --show-bin-path)
X86_BIN = $(shell swift build -c release --triple $(X86_TRIPLE) --show-bin-path)
UNIVERSAL := .build/universal
# The marketing version, and the build number: the commit count.
VERSION := $(shell cat VERSION)
BUILD := $(shell git rev-list --count HEAD)
RELEASE ?= 0
.PHONY: app run install zip selftest selftest-intel ui-snapshots cert clean icon devid-csr devid-import sparkle-keys \
	dmg-background dmg-venv release
app:
	swift build -c release --product Annotake --triple $(ARM_TRIPLE)
	swift build -c release --product Annotake --triple $(X86_TRIPLE)
	mkdir -p $(UNIVERSAL)
	lipo -create -output $(UNIVERSAL)/Annotake $(ARM_BIN)/Annotake $(X86_BIN)/Annotake
	RELEASE=$(RELEASE) VERSION=$(VERSION) BUILD=$(BUILD) FRAMEWORKS_DIR=$(ARM_BIN) \
		scripts/bundle-app.sh $(UNIVERSAL)/Annotake Annotake com.fayzanmalik.annotake build
run: app
	open build/Annotake.app
install: app
	rm -rf /Applications/Annotake.app ~/Applications/Annotake.app && ditto build/Annotake.app /Applications/Annotake.app
# Without resource forks, extended attributes, or ACLs: iCloud's tags and the provenance attribute stay out.
zip: app
	cd build && rm -f Annotake.zip && ditto -c -k --keepParent --norsrc --noextattr --noacl Annotake.app Annotake.zip
selftest: app
	rm -rf build/selftest && mkdir -p build/selftest
	caffeinate -u -t 2 || true
	open -W -n build/Annotake.app --args --selftest "$(CURDIR)/build/selftest"
	cat build/selftest/selftest.txt
	grep -q '^PASSED' build/selftest/selftest.txt
# The Intel half, through Rosetta.
selftest-intel: app
	rm -rf build/selftest-intel && mkdir -p build/selftest-intel
	caffeinate -u -t 2 || true
	open --arch x86_64 -W -n build/Annotake.app --args --selftest "$(CURDIR)/build/selftest-intel"
	cat build/selftest-intel/selftest.txt
	grep -q '^PASSED' build/selftest-intel/selftest.txt
	grep -q '^architecture: x86_64 (Rosetta)' build/selftest-intel/selftest.txt
ui-snapshots: app
	rm -rf build/ui && mkdir -p build/ui
	open -W -n build/Annotake.app --args --render-ui "$(CURDIR)/build/ui"
	ls build/ui
	@if [ -s build/ui/problems.txt ]; then cat build/ui/problems.txt; exit 1; fi
cert:
	scripts/make-cert.sh
# Redraws the disk image's background; Resources/dmg-background.tiff is committed.
dmg-background:
	rm -rf build/dmg-background
	swift scripts/make-dmg-background.swift build/dmg-background
	tiffutil -cathidpicheck build/dmg-background/background.tiff build/dmg-background/background@2x.tiff \
		-out Resources/dmg-background.tiff
# dmgbuild, which lays out the disk image, in its own Python environment.
DMG_VENV := .build/dmgbuild-venv
dmg-venv:
	rm -rf $(DMG_VENV)
	/usr/bin/python3 -m venv $(DMG_VENV)
	$(DMG_VENV)/bin/pip install -q dmgbuild==1.6.5
# A release: make release NOTES="what changed" [DRY_RUN=1] (scripts/release.sh). DRY_RUN=1 runs it all
# locally, without credentials, and publishes nothing.
export NOTES DRY_RUN
release:
	scripts/release.sh
# The Developer ID Application certificate: the request to upload to Apple, then the certificate it issues.
devid-csr:
	scripts/devid.sh csr
devid-import:
	scripts/devid.sh import "$(CER)"
# Sparkle's update-signing key: the public half is committed, the private half stays in .signing and the keychain.
sparkle-keys:
	scripts/sparkle-keys.sh
# Redraws the app icon; Resources/AppIcon.icns is committed. The script draws the mark from the app's own
# BrandMark.swift, so the two are compiled together.
icon:
	rm -rf build/AppIcon.iconset && mkdir -p build Resources
	swiftc -parse-as-library -o build/make-icon scripts/make-icon.swift Sources/AnnotakeApp/BrandMark.swift
	build/make-icon build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
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
