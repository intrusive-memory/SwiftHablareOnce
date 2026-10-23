// swift-tools-version: 6.2

import Foundation
import PackageDescription

// In CI we always pin to released remotes. Locally, prefer a sibling checkout
// at ../<name> if present so in-flight changes can be exercised end-to-end
// without publishing a release. Falls back to the remote pin if the sibling
// directory is missing, so fresh clones still build.
let useLocalSiblings = ProcessInfo.processInfo.environment["CI"] != "true"

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, .upToNextMajor(from: version))
}

let package = Package(
  name: "SwiftHablareOnce",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
  ],
  products: [
    .library(
      name: "SwiftHablareOnce",
      targets: ["SwiftHablareOnce"]
    )
  ],
  dependencies: [
    sibling(
      "SwiftHablare",
      remote: "https://github.com/intrusive-memory/SwiftHablare.git",
      from: "6.3.0"
    ),
    sibling(
      "SwiftOnce",
      remote: "https://github.com/intrusive-memory/SwiftOnce.git",
      from: "1.0.0"
    ),
  ],
  targets: [
    .target(
      name: "SwiftHablareOnce",
      dependencies: [
        .product(name: "SwiftHablare", package: "SwiftHablare"),
        .product(name: "SwiftOnce", package: "SwiftOnce"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
    .testTarget(
      name: "SwiftHablareOnceTests",
      dependencies: [
        "SwiftHablareOnce",
        .product(name: "SwiftHablare", package: "SwiftHablare"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("StrictConcurrency")
      ]
    ),
  ]
)
