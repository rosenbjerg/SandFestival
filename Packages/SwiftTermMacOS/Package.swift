// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "SwiftTermMacOS",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SwiftTermMacOS", targets: ["SwiftTermMacOS"]),
    ],
    dependencies: [
        // traits: [] drops PortableGraphics, which is the only thing pulling swift-png (and its dependency h) into the graph.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.99.1", traits: []),
    ],
    targets: [
        .target(
            name: "SwiftTermMacOS",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
    ]
)
