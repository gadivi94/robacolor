// swift-tools-version: 5.9
import PackageDescription

// El nombre del paquete y del producto tiene que ser «RobacolorRaw»: es el que Capacitor
// deduce del nombre npm «robacolor-raw» al generar ios/App/CapApp-SPM/Package.swift.
let package = Package(
    name: "RobacolorRaw",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "RobacolorRaw",
            targets: ["RawPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "8.0.0")
    ],
    targets: [
        .target(
            name: "RawPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/RawPlugin")
    ]
)
