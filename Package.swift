// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JsonTooling",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JSONCore", targets: ["JSONCore"])
    ],
    targets: [
        // Solo el núcleo y sus tests: la app la construye el proyecto de Xcode, que consume
        // este paquete como dependencia local. Antes había aquí un target ejecutable y el
        // código de la app acabó duplicado en los dos sitios.
        .target(name: "JSONCore"),
        .testTarget(name: "JSONCoreTests", dependencies: ["JSONCore"])
    ]
)
