// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "SwiftIOPackagePluginTest",
    platforms: [
        //.custom("thumbv7em-unknown-none-eabi", versionString: "0.0")
        .macOS(.v12)
    ],
    products: [
        .executable(name: "SwiftIOPackagePluginTest", targets: ["SwiftIOPackagePluginTest"])
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/madmachineio/SwiftIO.git", branch: "main"),
        .package(url: "https://github.com/madmachineio/MadBoards.git", branch: "main"),
        //.package(url: "https://github.com/madmachineio/MadDrivers.git", branch: "main"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "SwiftIOPackagePluginTest",
            dependencies: [
                "SwiftIO",
                "MadBoards",
                // use specific library would speed up the compile procedure
                //.product(name: "MadDrivers", package: "MadDrivers")
            ],
            swiftSettings: [
                //.unsafeFlags(["--destination", "\".build/destination.json\""])
                
            ],
            plugins: [
                //.plugin(name: "createDestinationFile")
            ]
        ),
        
        .plugin(name: "build",
                capability: .command(
                    intent: .custom(
                        verb: "build",
                        description: "Build the MadMachine project."),
                    permissions: [
                        .writeToPackageDirectory(reason: "In order to successfully build the project, we need access to the package directory")
                    ]
                )
        )
    ]
)
