// swift-tools-version:5.5
// Moth vendors the library without upstream test/documentation-only dependencies.
import PackageDescription
let package = Package(name: "TOMLKit", platforms: [.macOS(.v10_15)], products: [.library(name: "TOMLKit", targets: ["TOMLKit"])], targets: [.target(name: "CTOML", cxxSettings: [.define("TOML_EXCEPTIONS", to: "1")]), .target(name: "TOMLKit", dependencies: ["CTOML"], exclude: ["TOMLKit.docc"])], cLanguageStandard: .c99, cxxLanguageStandard: .cxx17)
