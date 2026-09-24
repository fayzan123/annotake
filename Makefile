KC := $(CURDIR)/.signing/flipbook-signing.keychain-db
.PHONY: cert spike spike-run spike-zip clean
cert:
	scripts/make-cert.sh
spike:
	cd spikes && swift build -c release
	scripts/bundle-app.sh spikes/.build/release/FlipbookSpike FlipbookSpike com.fayzanmalik.flipbook.spike build
spike-run: spike
	open build/FlipbookSpike.app
spike-zip: spike
	cd build && rm -f FlipbookSpike.zip && ditto -c -k --keepParent FlipbookSpike.app FlipbookSpike.zip
clean:
	rm -rf .build spikes/.build build
