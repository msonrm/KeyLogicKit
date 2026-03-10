// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeyLogicKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "KeyLogicKit", targets: ["KeyLogicKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", revision: "27af9c5cd6bfb5afd09ad00cb1b8b753d41e0982"),
    ],
    targets: [
        .target(
            name: "KeyLogicKit",
            dependencies: [
                .product(name: "KanaKanjiConverterModuleWithDefaultDictionary", package: "AzooKeyKanaKanjiConverter")
            ],
            path: "Sources/KeyLogicKit",
            resources: [
                .copy("Resources/Keymaps")
            ]
        ),
    ]
)
