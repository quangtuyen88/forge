// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ForgeCore",
  defaultLocalization: "en",
  platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
  products: [.library(name: "ForgeCore", targets: ["ForgeCore"])],
  targets: [
    .target(name: "ForgeCore", resources: [.process("Resources")]),
    .testTarget(name: "ForgeCoreTests", dependencies: ["ForgeCore"]),
  ]
)
