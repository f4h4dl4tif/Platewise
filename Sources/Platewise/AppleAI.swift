import Foundation

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum AIStatus: Equatable {
    case checking
    case ready
    case textOnly            // Apple Intelligence works but can't look at photos
    case unavailable(String)

    var canWrite: Bool { self == .ready || self == .textOnly }
    var canSee: Bool { self == .ready }
}

/// Talks to `platewise-ai`, the bundled helper that runs Apple's on-device model.
/// (Image input needs the macOS 27 SDK, which can't build the SwiftUI app with the Command Line Tools, so the
/// model code lives in its own small executable: Helper/PlatewiseAI.swift.) Nothing leaves the Mac.
enum AppleAI {
    static var helperURL: URL? { Bundle.main.url(forAuxiliaryExecutable: "platewise-ai") }

    static func status() async -> AIStatus {
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)) else {
            return .unavailable("Snap & Cook needs macOS 27 or later with Apple Intelligence. You can still plan meals, add recipes by hand and build grocery lists.")
        }
        guard let data = try? await run("status", [:], timeout: 30),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unavailable("Couldn't start Apple Intelligence. It needs a Mac with Apple silicon. Try reinstalling Platewise if this Mac has one.")
        }
        if obj["available"] as? Bool == true { return obj["vision"] as? Bool == true ? .ready : .textOnly }
        return .unavailable(obj["reason"] as? String ?? obj["error"] as? String ?? "Apple Intelligence isn't available right now.")
    }

    static func identify(imagePath: String, prompt: String) async throws -> IdentifyResult {
        try decode(try await run("identify", ["image_path": imagePath, "prompt": prompt]))
    }

    static func recipe(prompt: String) async throws -> Data {
        let data = try await run("recipe", ["prompt": prompt])
        try throwIfError(data)
        return data
    }

    // MARK: Plumbing

    private static func run(_ command: String, _ request: [String: Any], timeout: TimeInterval = 180) async throws -> Data {
        guard let url = helperURL else { throw AppError("Platewise's Apple Intelligence helper is missing. Please reinstall Platewise.") }
        let body = try JSONSerialization.data(withJSONObject: request)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = url
                process.arguments = [command]
                let input = Pipe(), output = Pipe()
                process.standardInput = input
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(throwing: AppError("Couldn't start Apple Intelligence (\(error.localizedDescription))."))
                    return
                }
                input.fileHandleForWriting.write(body)
                try? input.fileHandleForWriting.close()

                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: AppError("Apple Intelligence took too long. Please try again."))
                } else if data.isEmpty {
                    continuation.resume(throwing: AppError("Apple Intelligence stopped without an answer. Please try again."))
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    private static func throwIfError(_ data: Data) throws {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let message = obj["error"] as? String {
            throw AppError(message)
        }
    }

    static func decode<T: Decodable>(_ data: Data) throws -> T {
        try throwIfError(data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) } catch {
            throw AppError("Apple Intelligence's answer wasn't in the expected format. Please try again.")
        }
    }
}
