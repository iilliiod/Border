//
//  ImageMagickProcessor.swift
//  bordr
//
//  Created by v on 7/22/25.
//

import Foundation

/// Thin, async wrapper around the ImageMagick CLI (`magick` / `magick montage`).
class ImageMagickProcessor {

	// MARK: - Executable discovery

	/// Locates the `magick` executable, preferring Homebrew's Apple-silicon path.
	private func magickPath() throws -> String {
		let candidates = [
			"/opt/homebrew/bin/magick",
			"/usr/local/bin/magick",
			"/usr/bin/magick"
		]
		for path in candidates where FileManager.default.fileExists(atPath: path) {
			return path
		}
		throw ImageMagickError.executableNotFound
	}

	/// Runs a prepared `Process` and bridges its termination into `async`.
	private func run(_ process: Process) async throws {
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe

		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			process.terminationHandler = { currentProcess in
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				let output = String(data: data, encoding: .utf8) ?? ""

				if currentProcess.terminationStatus == 0 {
					continuation.resume()
				} else {
					continuation.resume(
						throwing: ImageMagickError.commandFailed(
							statusCode: currentProcess.terminationStatus,
							message: output
						)
					)
				}
			}

			do {
				try process.run()
			} catch {
				continuation.resume(throwing: error)
			}
		}
	}

	private func makeShellProcess(command: String) -> Process {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-c", command]
		return process
	}

	// MARK: - processImage()

	/// Processes a single image using an ImageMagick CLI command.
	/// - Returns: The URL of the successfully processed output image.
	func processImage(inputPath: URL, outputPath: URL, commandArguments: [String]) async throws -> URL {
		guard FileManager.default.fileExists(atPath: inputPath.path) else {
			throw ImageMagickError.fileNotFound(inputPath)
		}

		var parts = [try magickPath().shellEscaped(), inputPath.path.shellEscaped()]
		parts.append(contentsOf: commandArguments)
		parts.append(outputPath.path.shellEscaped())

		try await run(makeShellProcess(command: parts.joined(separator: " ")))
		return outputPath
	}

	// MARK: - processCollage()

	/// Builds a montage/contact sheet from multiple input images.
	func processCollage(inputPaths: [URL], outputPath: URL, commandArguments: [String]) async throws -> URL {
		try inputPaths.forEach { inputPath in
			guard FileManager.default.fileExists(atPath: inputPath.path) else {
				throw ImageMagickError.fileNotFound(inputPath)
			}
		}

		var parts = [try magickPath().shellEscaped(), "montage"]
		parts.append(contentsOf: inputPaths.map { $0.path.shellEscaped() })
		parts.append(contentsOf: commandArguments)
		parts.append(outputPath.path.shellEscaped())

		try await run(makeShellProcess(command: parts.joined(separator: " ")))
		return outputPath
	}

	// MARK: - process4Scroll()

	/// Slices a single image into several output files in one shell invocation.
	///
	/// Each entry in `commandArguments` describes one slice (without its output
	/// path); the matching entry in `outputPaths` receives the result.
	func process4Scroll(inputPath: URL, outputPaths: [URL], commandArguments: [[String]]) async throws -> [URL] {
		guard FileManager.default.fileExists(atPath: inputPath.path) else {
			throw ImageMagickError.fileNotFound(inputPath)
		}
		guard commandArguments.count == outputPaths.count, !outputPaths.isEmpty else {
			throw ImageMagickError.commandFailed(statusCode: -1, message: "Mismatched scroll arguments and outputs.")
		}

		let magick = try magickPath().shellEscaped()
		let commands: [String] = zip(commandArguments, outputPaths).map { args, output in
			var parts = [magick, inputPath.path.shellEscaped()]
			parts.append(contentsOf: args)
			parts.append(output.path.shellEscaped())
			return parts.joined(separator: " ")
		}

		try await run(makeShellProcess(command: commands.joined(separator: " && ")))
		return outputPaths
	}
}

enum ImageMagickError: Error, LocalizedError {
	case fileNotFound(URL)
	case fileAlreadyExists(URL)
	case commandFailed(statusCode: Int32, message: String)
	case executableNotFound

	var errorDescription: String? {
		switch self {
			case .fileNotFound(let url): return "Input file not found: \(url.lastPathComponent)"
			case .fileAlreadyExists(let url): return "Output file already exists: \(url.lastPathComponent)"
			case .commandFailed(let statusCode, let message):
				let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
				return "ImageMagick failed (\(statusCode)): \(trimmed.isEmpty ? "unknown error" : trimmed)"
			case .executableNotFound:
				return "ImageMagick 'magick' not found. Install it via Homebrew (e.g. /opt/homebrew/bin/magick)."
		}
	}
}

// MARK: - Shell escaping helper

extension String {
	func shellEscaped() -> String {
		guard self.rangeOfCharacter(from: CharacterSet(charactersIn: " \"'\\$!*?[]{}<>()`~#&|;")) != nil else {
			return self
		}
		return "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}
