# SwiftHablareOnce Makefile
# ElevenLabs VoiceProvider package for SwiftHablare.

SCHEME = SwiftHablareOnce
DESTINATION = platform=macOS,arch=arm64
DERIVED_DATA = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: all build test resolve lint clean help

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
	xcodebuild test -scheme $(SCHEME) -destination '$(DESTINATION)'

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
	@echo "  test     - Run tests"
	@echo "  lint     - Format Swift source files"
	@echo "  clean    - Clean build artifacts"
	@echo "  help     - Show this help"
	@echo ""
	@echo "All builds use: -destination '$(DESTINATION)'"
