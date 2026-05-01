//
//  HablareAliases.swift
//  SwiftHablareOnce
//
//  Module-scope typealiases for SwiftHablare types that collide with names
//  exported by SwiftOnce when both modules are imported into the same file.
//
//  Defined in a file that imports only SwiftHablare so the unqualified `Voice`
//  identifier resolves unambiguously to `SwiftHablare.Voice`.
//

import SwiftHablare

public typealias HablareVoice = Voice
