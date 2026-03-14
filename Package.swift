// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeyLogicKit",
    platforms: [.iOS(.v18)],
    traits: [
        .trait(name: "ZenzaiCPU", description: "Zenzai ニューラル変換（CPU）を有効にする"),
    ],
    products: [
        .library(name: "KeyLogicKit", targets: ["KeyLogicKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter",
                 revision: "27af9c5cd6bfb5afd09ad00cb1b8b753d41e0982",
                 traits: [
                     .trait(name: "ZenzaiCPU", condition: .when(traits: ["ZenzaiCPU"])),
                 ]),
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
