// swift-tools-version: 6.2

import PackageDescription

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
    .package(
      url: "https://github.com/intrusive-memory/SwiftHablare.git", .upToNextMajor(from: "6.3.0")),
    .package(
      url: "https://github.com/intrusive-memory/SwiftOnce.git", .upToNextMajor(from: "1.0.0")),
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
