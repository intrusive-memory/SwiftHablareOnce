# Claude-Specific Agent Instructions

**⚠️ Read [AGENTS.md](AGENTS.md) first** for universal project documentation.

This file contains instructions specific to Claude Code agents working on SwiftHablareOnce.

## Build Tool Preferences

From global `~/.claude/CLAUDE.md`:

**CRITICAL**: NEVER use `swift build` or `swift test`. ALWAYS use `xcodebuild` (or
XcodeBuildMCP tools when available) instead.

- **Local builds**: Use XcodeBuildMCP tools (`swift_package_build`, `swift_package_test`,
  `build_macos`, `test_macos`, etc.)
- **CI/CD workflows**: Use `xcodebuild build` and `xcodebuild test` with appropriate
  `-scheme` and `-destination` flags

**For SwiftHablareOnce**: Use the Makefile targets which wrap the correct `xcodebuild`
commands (`make build`, `make test`, `make lint`, `make clean`, `make resolve`).

## Critical Rules

1. **ALWAYS use Makefile targets**
2. **NEVER use `swift build` or `swift test`** — Use XcodeBuildMCP or Makefile targets
3. **Run `make lint` before committing** — Formats all Swift source files
4. **Follow the sibling pattern** when adding dependencies; mirror what SwiftHablare and
   SwiftVoxAlta already use
5. **iOS 26.0+ / macOS 26.0+ only** — never add code paths for older platforms

## Module Collision (Voice type)

`SwiftHablare.Voice` and `SwiftOnce.Voice` collide whenever both modules are imported into
the same file. The `SwiftHablare` namespace struct shadows the module name, so explicit
`SwiftHablare.Voice` qualification does not work. Use the `HablareVoice` typealias declared
in `Sources/SwiftHablareOnce/HablareAliases.swift` — that file imports only SwiftHablare so
the symbol resolves cleanly there.

## Global Claude Settings

Your global Claude instructions: `~/.claude/CLAUDE.md`

Key patterns from global settings:
- **Communication Style**: Complete candor — flag risks and concerns directly
- **Security**: NEVER expose secrets, API keys, or credentials
- **Swift Build Preference**: Always use `xcodebuild` over `swift build/test`
- **Makefile-First Projects**: SwiftHablareOnce has a Makefile — use `make` targets
- **GitHub Actions CI/CD**: Always use `macos-26` or later runners with Swift 6.2+
