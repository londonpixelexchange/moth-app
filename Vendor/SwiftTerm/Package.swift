// swift-tools-version:5.9
// Lume vendors only the library target; upstream CLI dependencies are deliberately omitted.
import PackageDescription
let package = Package(name: "SwiftTerm", platforms: [.macOS(.v13)], products: [.library(name: "SwiftTerm", targets: ["SwiftTerm"])], targets: [.target(name: "SwiftTerm", path: "Sources/SwiftTerm", exclude: ["Mac/README.md"]), .testTarget(name: "SwiftTermTests", dependencies: ["SwiftTerm"], path: "Tests/SwiftTermTests")], swiftLanguageVersions: [.v5])
