// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "KaiTagAlly",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "KaiTagAlly", targets: ["KaiTagAlly"])
    ],
    dependencies: [
        .package(url: "https://github.com/socketio/socket.io-client-swift.git", from: "16.0.0")
    ],
    targets: [
        .target(
            name: "KaiTagAlly",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ]
        )
    ]
) 