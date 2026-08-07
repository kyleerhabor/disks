// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "DisksCore",
  platforms: [.macOS(.v15)],
  products: [.library(name: "DisksCoreDiskArbitration", targets: ["DisksCoreDiskArbitration"])],
  targets: [.target(name: "DisksCoreDiskArbitration")]
)
