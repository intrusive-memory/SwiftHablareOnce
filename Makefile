# SwiftHablareOnce Makefile
# ElevenLabs VoiceProvider package for SwiftHablare.

SCHEME = SwiftHablareOnce
LIVE_TESTS ?= SwiftHablareOnceLiveTests
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: all build test test-live resolve lint clean help

all: build

# Resolve all SPM package dependencies via xcodebuild
resolve:
	xcodebuild -resolvePackageDependencies -scheme $(SCHEME) -destination '$(DESTINATION)'
	@echo "Package dependencies resolved."

# Library build via xcodebuild
build: resolve
	xcodebuild build -scheme $(SCHEME) -destination '$(DESTINATION)'
	@echo "Build complete."

# Run tests
test: resolve
	xcodebuild test -scheme $(SCHEME) -destination '$(DESTINATION)' -skip-testing:SwiftHablareOnceLiveTests

# Live ElevenLabs tests (spends ~100 characters and one voice design; needs ELEVENLABS_API_KEY).
# The key is passed to the test runner through the environment and never printed.
test-live: resolve
	@test -n "$$ELEVENLABS_API_KEY" || { echo "ELEVENLABS_API_KEY is not set; the live tests would be skipped."; exit 1; }
	@TEST_RUNNER_ELEVENLABS_API_KEY="$$ELEVENLABS_API_KEY" xcodebuild test -scheme $(SCHEME) -destination '$(DESTINATION)' '-only-testing:$(LIVE_TESTS)'

# Format Swift source files
lint:
	swift format -i -r .

# Clean build artifacts
clean:
	swift package clean
	rm -rf $(DERIVED_DATA)/SwiftHablareOnce-*

help:
	@echo "SwiftHablareOnce Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  resolve  - Resolve all SPM package dependencies"
	@echo "  build    - Library build with xcodebuild (default)"
	@echo "  test     - Run offline tests (conformance with mocked HTTP; skips live tests)"
	@echo "  test-live - Run gated live ElevenLabs tests (needs ELEVENLABS_API_KEY)"
	@echo "  lint     - Format Swift source files"
	@echo "  clean    - Clean build artifacts"
	@echo "  help     - Show this help"
	@echo ""
	@echo "All builds use: -destination '$(DESTINATION)'"
