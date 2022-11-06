//
//  Build.swift
//  
//
//  Created by Omer Shamai on 26/10/2022.
//

import Foundation
import PackagePlugin

class CRC32 {
        
    static var table: [UInt32] = {
        (0...255).map { i -> UInt32 in
            (0..<8).reduce(UInt32(i), { c, _ in
                (c % 2 == 0) ? (c >> 1) : (0xEDB88320 ^ (c >> 1))
            })
        }
    }()

    static func checksum(bytes: [UInt8]) -> UInt32 {
        return ~(bytes.reduce(~UInt32(0), { crc, byte in
            (crc >> 8) ^ table[(Int(crc) ^ Int(byte)) & 0xFF]
        }))
    }
}

enum CreateDestinationError: Error {
    case failedToReadMMPFile
}

struct MadMachinePackage: Decodable {
    let board: String
    let triple: String
    let version: Int
}

struct DestinationFile: Codable {
    let extraCCFlags: [String]
    let extraCPPFlags: [String]
    let extraSwiftcFlags: [String]
    let sdk: String
    let target: String
    let toolchainBinDir: String
    let version: Int
    
    enum CodingKeys: String, CodingKey {
        case extraCCFlags = "extra-cc-flags"
        case extraCPPFlags = "extra-cpp-flags"
        case extraSwiftcFlags = "extra-swiftc-flags"
        case sdk
        case target
        case toolchainBinDir = "toolchain-bin-dir"
        case version
    }
}

fileprivate var tomlContent: MadMachinePackage!

fileprivate let SWIFTIO_BOARD = ["vid": "0x1fc9",
                "pid": "0x0093",
                "serial_number": "012345671FC90093",
                "sd_image_name": "swiftio.bin",
                "usb2serial_device": "DAPLink CMSIS-DAP"]

fileprivate let SWIFTIO_FEATHER = ["vid": "0x1fc9",
                    "pid": "0x0095",
                    "serial_number": "012345671FC90095",
                    "sd_image_name": "feather.img",
                    "usb2serial_device": "CP21"]

fileprivate let IMAGE_HEADER_CAPACITY: UInt64 = 1024 * 4

fileprivate let IMAGE_START_OFFSET: UInt64 = IMAGE_HEADER_CAPACITY  // Default 4k offset
fileprivate let IMAGE_LOAD_ADDRESS: UInt64 = 0x80000000             // SDRAM start address
fileprivate let IMAGE_TYPE: UInt32 = 0x20                           // User app 0
fileprivate let IMAGE_VERIFY_TYPE: UInt32 = 0x01                    // CRC32
fileprivate let IMAGE_VERIFY_CAPACITY: UInt64 = 64                  // 64 bytes capacity

protocol UIntToBytesConvertable {
    var toBytes: [UInt8] { get }
}

extension UIntToBytesConvertable {
    func toByteArr<T: BinaryInteger>(endian: T, count: Int) -> [UInt8] {
        var _endian = endian
        let bytePtr = withUnsafePointer(to: &_endian) {
            $0.withMemoryRebound(to: UInt8.self, capacity: count) {
                UnsafeBufferPointer(start: $0, count: count)
            }
        }
        return [UInt8](bytePtr)
    }
}

extension UInt32: UIntToBytesConvertable {
    var toBytes: [UInt8] {
        if CFByteOrderGetCurrent() == Int(CFByteOrderLittleEndian.rawValue) {
        return toByteArr(endian: self.littleEndian,
                         count: MemoryLayout<UInt32>.size)
        } else {
            return toByteArr(endian: self.bigEndian,
                             count: MemoryLayout<UInt32>.size)
        }
    }
}

extension UInt64: UIntToBytesConvertable {
    var toBytes: [UInt8] {
        if CFByteOrderGetCurrent() == Int(CFByteOrderLittleEndian.rawValue) {
        return toByteArr(endian: self.littleEndian,
                         count: MemoryLayout<UInt64>.size)
        } else {
            return toByteArr(endian: self.bigEndian,
                             count: MemoryLayout<UInt64>.size)
        }
    }
}

@main
struct Build: CommandPlugin {
    
    func getGCCIncludePath() -> [String] {
        // Get the SDK path
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["-toolchain", "io.madmachine.swift", "--find", "swift"]
        try! task.run()
        
        let data = try! pipe.fileHandleForReading.readToEnd()
        let output = String(data: data ?? Data(), encoding: .utf8)!
        
        let sdkPath = Path(output).removingLastComponent().removingLastComponent().removingLastComponent()
        
        return [
            "-I\(sdkPath)/usr/arm-none-eabi/include",
            "-I\(sdkPath)/usr/lib/clang/13.0.0/include"
        ]
    }
    
    func getCPredefined() -> [String] {
        return [
            "-nostdinc",
            "--rtlib=libgcc",
            "-Wno-unused-command-line-argument",
            "-D__MADMACHINE__",
            "-D_POSIX_THREADS",
            "-D_POSIX_READER_WRITER_LOCKS",
            "-D_UNIX98_THREAD_MUTEX_ATTRIBUTES"
        ]
    }
    
    func getCArch() -> [String] {
        if tomlContent.triple == "thumbv7em-unknown-none-eabihf" {
            return [
                "-mcpu=cortex-m7",
                "-mhard-float",
                "-mfloat-abi-hard"
            ]
        } else {
            return [
                "-mcpu=cortex-m7+nofp",
                "-msoft-float",
                "-mfloat-abi=soft"
            ]
        }
    }
    
    func getCCFlags(projectType: String) -> [String] {
        var flags = [String]()
        
        flags.append(contentsOf: getCArch())
        flags.append(contentsOf: getCPredefined())
        flags.append(contentsOf: getGCCIncludePath())
        
        return flags
    }
    
    func getSwiftGCCLibrary() -> [String] {
        var flags = [
            "-Xlinker --start-group",
            "-Xlinker -lstdc++",
            "-Xlinker -lc",
            "-Xlinker -lg",
            "-Xlinker -lm",
            "-Xlinker -lgcc",
            "-Xlinker --end-group"
        ]
        
        flags = flags.joined(separator: " ").components(separatedBy: " ")
        
        return flags
    }
    
    func getSwiftBoardLibrary() -> [String] {
        // Get SDK Path
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["-toolchain", "io.madmachine.swift", "--find", "swift"]
        try! task.run()
        
        let data = try! pipe.fileHandleForReading.readToEnd()
        let output = String(data: data ?? Data(), encoding: .utf8)!
        
        let sdkPath = Path(output).removingLastComponent().removingLastComponent().removingLastComponent()
        
        var subPath: String!
        
        if tomlContent.triple == "thumbv7em-unknown-none-eabihf" {
            subPath = "eabihf"
        } else {
            subPath = "eabi"
        }
        
        var libraries = ["--whole-archive"]
        libraries.append(contentsOf: try! FileManager.default.contentsOfDirectory(atPath: "\(sdkPath)/Boards/\(tomlContent.board)/lib/thumbv7em/\(subPath!)/whole").filter({ $0.hasSuffix(".obj") }).sorted().map { "\(sdkPath)/Boards/\(tomlContent.board)/lib/thumbv7em/\(subPath!)/whole/\($0)" })
        libraries.append(contentsOf: try! FileManager.default.contentsOfDirectory(atPath: "\(sdkPath)/Boards/\(tomlContent.board)/lib/thumbv7em/\(subPath!)/whole").filter({ $0.hasSuffix(".a") }).sorted().map { "\(sdkPath)/Boards/\(tomlContent.board)/lib/thumbv7em/\(subPath!)/whole/\($0)" })
        
        libraries.append("--no-whole-archive")
        libraries.append(contentsOf: try! FileManager.default.contentsOfDirectory(atPath: "\(sdkPath)/Boards/\(tomlContent.board)/lib/thumbv7em/\(subPath!)/nowhole").filter({ $0.hasSuffix(".obj") }).sorted().map { "\(sdkPath)/Boards/\(tomlContent.board)/lib/thumbv7em/\(subPath!)/nowhole/\($0)" })
        libraries.append(contentsOf: try! FileManager.default.contentsOfDirectory(atPath: "\(sdkPath)/Boards/\(tomlContent.board)/lib/thumbv7em/\(subPath!)/nowhole").filter({ $0.hasSuffix(".a") }).sorted().map { "\(sdkPath)/Boards/\(tomlContent.board)/lib/thumbv7em/\(subPath!)/nowhole/\($0)" })
        
        var flags = libraries.map { "-Xlinker \($0)" }
        flags = flags.joined(separator: " ").components(separatedBy: " ")
        
        return flags
    }
    
    func getSwiftLinkSearchPath() -> [String] {
        // Get SDK Path
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["-toolchain", "io.madmachine.swift", "--find", "swift"]
        try! task.run()
        
        let data = try! pipe.fileHandleForReading.readToEnd()
        let output = String(data: data ?? Data(), encoding: .utf8)!
        
        let sdkPath = Path(output).removingLastComponent().removingLastComponent().removingLastComponent()
        
        var subPath: String!
        
        if tomlContent.triple == "thumbv7em-unknown-none-eabihf" {
            subPath = "/v7e-m+dp/hard"
        } else {
            subPath = "/v7e-m/nofp"
        }
        
        return [
            "-L\(sdkPath)/usr/lib/gcc/arm-none-eabi/10.3.1/thumb\(subPath!)",
            "-L\(sdkPath)/usr/arm-none-eabi/lib/thumb\(subPath!)"
        ]
    }
    
    func getSwiftLinkerScript() -> [String] {
        // Get SDK Path
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["-toolchain", "io.madmachine.swift", "--find", "swift"]
        try! task.run()
        
        let data = try! pipe.fileHandleForReading.readToEnd()
        let output = String(data: data ?? Data(), encoding: .utf8)!
        
        let sdkPath = Path(output).removingLastComponent().removingLastComponent().removingLastComponent()
        
        var flags = [
            "-Xlinker -T",
            "-Xlinker \(sdkPath)/Boards/\(tomlContent.board)/linker/sdram.ld"
        ]
        
        flags = flags.joined(separator: " ").components(separatedBy: " ")
        
        return flags
    }
    
    func getSwiftLinkerConfig(path: String, projectName: String) -> [String] {
        let mapPath = "\(path)/\(projectName).map"
        
        var flags = [
            "-Xlinker -u,_OffsetAbsSyms",
            "-Xlinker -u,_ConfigAbsSyms",
            "-Xlinker -X",
            "-Xlinker -N",
            "-Xlinker --gc-sections",
            "-Xlinker --build-id=none",
            "-Xlinker --sort-common=descending",
            "-Xlinker --sort-section=alignment",
            "-Xlinker --print-memory-usage",
            "-Xlinker -Map",
            "-Xlinker \(mapPath)"
        ]
        
        flags = flags.joined(separator: " ").components(separatedBy: " ")
        
        return flags
    }
    
    func getSwiftClangHeader() -> [String] {
        // Get SDK Path
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["-toolchain", "io.madmachine.swift", "--find", "swift"]
        try! task.run()
        
        let data = try! pipe.fileHandleForReading.readToEnd()
        let output = String(data: data ?? Data(), encoding: .utf8)!
        
        let sdkPath = Path(output).removingLastComponent().removingLastComponent().removingLastComponent()
        
        var flags = [
            "-I \(sdkPath)/usr/arm-none-eabi/include",
            "-I \(sdkPath)/usr/lib/clang/13.0.0/include"
        ]
        
        flags = flags.joined(separator: " ").components(separatedBy: " ")
        
        for (idx, _) in flags.enumerated() {
            flags[idx] = "-Xcc \(flags[idx])"
        }
        
        flags = flags.joined(separator: " ").components(separatedBy: " ")
        return flags
    }
    
    func getSwiftGCCHeader() -> [String] {
        // Get SDK Path
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["-toolchain", "io.madmachine.swift", "--find", "swift"]
        try! task.run()
        
        let data = try! pipe.fileHandleForReading.readToEnd()
        let output = String(data: data ?? Data(), encoding: .utf8)!
        
        let sdkPath = Path(output).removingLastComponent().removingLastComponent().removingLastComponent()
        
        var flags = [
            "-I \(sdkPath)/usr/arm-none-eabi/include",
            "-I \(sdkPath)/usr/lib/gcc/arm-none-eabi/10.3.1/include",
            "-I \(sdkPath)/usr/lib/gcc/arm-none-eabi/10.3.1/include-fixed"
        ]
        
        flags = flags.joined(separator: " ").components(separatedBy: " ")
        
        for (idx, _) in flags.enumerated() {
            flags[idx] = "-Xcc \(flags[idx])"
        }
        
        flags = flags.joined(separator: " ").components(separatedBy: " ")
        return flags
    }
    
    func getSwiftPredefined(projectType: String) -> [String] {
        var flags = [
            "-static-stdlib",
            "-Xfrontend",
            "-function-sections",
            "-Xfrontend",
            "-data-sections",
            "-Xcc",
            "-D__MADMACHINE__",
            "-Xcc",
            "-D_POSIZ_THREADS",
            "-Xcc",
            "-D_POSIX_READER_WRITER_LOCKS",
            "-Xcc",
            "-D_UNIX98_THREAD_MUTEX_ATTRIBUTES"
        ]
        
        if projectType == "executable" {
            flags.append("-static-executable")
        } else {
            flags.append("-static")
        }
        
        if tomlContent.board.count != 0 {
            flags.append("-D\(tomlContent.board.uppercased())")
        } else if projectType == "executable" {
            print("WARNING: board is missing in Package.mmp")
        }
        
        return flags
    }
    
    func getSwiftArch() -> [String] {
        if tomlContent.triple == "thumbv7em-unknown-none-eabihf" {
            return [
                "-target",
                "thumbv7em-unknown-none-eabihf",
                "-target-cpu",
                "cortex-m7",
                "-Xcc",
                "-mhard-float",
                "-Xcc",
                "-mfloat-abi=hard"
            ]
        } else {
            return [
                "-target",
                "thumbv7em-unknown-none-eabi",
                "-target-cpu",
                "cortex-m7+nofp",
                "-Xcc",
                "-msoft-float",
                "-Xcc",
                "-mfloat-abi=soft"
            ]
        }
    }
    
    func getSwiftcFlags(projectType: String, path: String, projectName: String) -> [String] {
        var flags = [String]()
        
        flags.append(contentsOf: getSwiftArch())
        flags.append(contentsOf: getSwiftPredefined(projectType: projectType))
        flags.append(contentsOf: getSwiftGCCHeader())
        
        if projectType == "executable" {
            flags.append(contentsOf: getSwiftLinkerConfig(path: path, projectName: projectName))
            flags.append(contentsOf: getSwiftLinkerScript())
            flags.append(contentsOf: getSwiftLinkSearchPath())
            flags.append(contentsOf: getSwiftBoardLibrary())
            flags.append(contentsOf: getSwiftGCCLibrary())
        }
        
        return flags
    }
    
    func makeDestination(projectType: String, path: String, projectName: String) -> String {
        let ccFlags = getCCFlags(projectType: projectType)
        let swiftcFlags = getSwiftcFlags(projectType: projectType, path: path, projectName: projectName)
        
        // Get SDK Path
        
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["-toolchain", "io.madmachine.swift", "--find", "swift"]
        try! task.run()
        
        let data = try! pipe.fileHandleForReading.readToEnd()
        let output = String(data: data ?? Data(), encoding: .utf8)!
        
        let binDir = Path(output).removingLastComponent()
        
        let sdkPath = Path(output).removingLastComponent().removingLastComponent().removingLastComponent()
        
        /*var destinationDictionary: [String: Any] = [
            "extra-cc-flags": ccFlags,
            "extra-cpp-flags": ccFlags,
            "extra-swiftc-flags": swiftcFlags,
            "sdk": sdkPath,
            "target": tomlContent.triple,
            "toolchain-bin-dir": binDir,
            "version": 1
        ]*/
        
        let destinationFile = DestinationFile(extraCCFlags: ccFlags, extraCPPFlags: ccFlags, extraSwiftcFlags: swiftcFlags, sdk: sdkPath.string, target: tomlContent.triple, toolchainBinDir: binDir.string, version: 1)
        
        //return String(data: try! JSONSerialization.data(withJSONObject: destinationDictionary, options: .prettyPrinted), encoding: .ascii)!
        
        return String(data: try! JSONEncoder().encode(destinationFile), encoding: .utf8)!
    }
    
    
    
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let mmpData = FileManager.default.contents(atPath: "\(context.package.directory)/Package.mmp")
        
        guard let mmpData = mmpData else {
            throw CreateDestinationError.failedToReadMMPFile
        }
        
        tomlContent = try TOMLDecoder().decode(MadMachinePackage.self, from: mmpData)
        
        let projectName = context.package.displayName
        var projectType: String!
        
        for executableProduct in context.package.products(ofType: ExecutableProduct.self) {
            if executableProduct.name == projectName {
                projectType = "executable"
                break
            }
        }
        
        if projectType == nil {
            for libraryProduct in context.package.products(ofType: LibraryProduct.self) {
                if libraryProduct.name == projectName {
                    projectType = "library"
                    break
                }
            }
        }
        
        if projectType == nil {
            projectType = "library"
        }
        
        var path = ""
        
        if projectType == "executable" {
            path = context.package.directory.appending([".build", tomlContent.triple, "release"]).string
        }
        
        let jsonData = makeDestination(projectType: projectType, path: path, projectName: projectName)
        
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: "\(context.package.directory)/.build"), withIntermediateDirectories: false)
        
        let destinationPath = Path("\(context.package.directory)/.build/destination.json")
        
        try! jsonData.write(toFile: destinationPath.string, atomically: false, encoding: .utf8)
        
        let buildProcess = Process()
        buildProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        buildProcess.arguments = ["-toolchain", "io.madmachine.swift", "swift", "build", "-c", "release", "--destination", ".build/destination.json"]
        
        try buildProcess.run()
        buildProcess.waitUntilExit()
        
        // Create final binary file
        if projectType == "executable" && FileManager.default.fileExists(atPath: "\(context.package.directory)/.build/\(tomlContent.triple)/release/\(projectName)") {
            let elfPath = "\(context.package.directory)/.build/\(tomlContent.triple)/release/\(projectName)"
            let path = "\(context.package.directory)/.build/\(tomlContent.triple)/release"
            let binPath = elfPath + ".bin"
            
            // create intermediate bin file
            let makeIntermediateBinFileProc = Process()
            makeIntermediateBinFileProc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            
            makeIntermediateBinFileProc.arguments = [
                "-toolchain",
                "io.madmachine.swift",
                "arm-none-eabi-objcopy",
                "-S",
                "-Obinary",
                "--gap-fill",
                "0xFF",
                "-R",
                ".comment",
                "-R",
                "COMMON",
                "-R",
                ".eh_frame",
                "\(elfPath)",
                "\(binPath)"
            ]
            
            try makeIntermediateBinFileProc.run()
            makeIntermediateBinFileProc.waitUntilExit()
            
            // Create final binary
            let imageName = (tomlContent.board == "SwiftIOFeather" ? SWIFTIO_FEATHER : SWIFTIO_BOARD)["sd_image_name"]!
            
            if tomlContent.board == "SwiftIOFeather" {
                let loadAddress = IMAGE_LOAD_ADDRESS
                
                print("Creating image \(imageName)...")
                
                let imageRawBinary = try! Data(contentsOf: URL(fileURLWithPath: binPath))
                
                let imageOffset = IMAGE_START_OFFSET.littleEndian
                let imageSize = UInt64(imageRawBinary.count).littleEndian
                let imageLoadAddress = loadAddress.littleEndian
                let imageType = IMAGE_TYPE.littleEndian
                let imageVerifyType = IMAGE_VERIFY_TYPE.littleEndian
                var imageCRC = CRC32.checksum(bytes: [UInt8](imageRawBinary)).littleEndian.toBytes
                imageCRC.append(contentsOf: [UInt8](repeating: 0x00, count: Int(IMAGE_VERIFY_CAPACITY - 4)))
                
                var imageHeader = imageOffset.toBytes
                imageHeader.append(contentsOf: imageSize.toBytes)
                imageHeader.append(contentsOf: imageLoadAddress.toBytes)
                imageHeader.append(contentsOf: imageType.toBytes)
                imageHeader.append(contentsOf: imageVerifyType.toBytes)
                imageHeader.append(contentsOf: imageCRC)
                
                let headerCRC = CRC32.checksum(bytes: imageHeader).littleEndian.toBytes
                
                imageHeader = headerCRC + imageHeader
                
                let headerBlock = imageHeader + [UInt8](repeating: 0xFF, count: Int(IMAGE_HEADER_CAPACITY) - imageHeader.count)
                
                try! Data(headerBlock + imageRawBinary).write(to: URL(fileURLWithPath: "\(path)/\(imageName)"))
            } else if tomlContent.board == "SwiftIOBoard" {
                print("Creating image \(imageName)...")
                let imagePath = path + "/\(imageName)"
                
                let imageRawBinary = try! Data(contentsOf: URL(fileURLWithPath: binPath))
                let imageCRC = CRC32.checksum(bytes: [UInt8](imageRawBinary)).toBytes
                
                try! Data(imageRawBinary + imageCRC).write(to: URL(fileURLWithPath: "\(path)/\(imageName)"))
            }
        }
        
        /*return [.buildCommand(displayName: "Running build...",
                              executable: Path("/usr/bin/xcrun"),
                              arguments: ["-toolchain", "io.madmachine.swift", "swift", "build", "-c", "release", "--destination", "\".build/destination.json\""],
                             environment: ["DID_GENERATE"])]*/
        
    }
}
