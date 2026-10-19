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

	/// Runs `magick` with an argument vector (no shell) and bridges it into `async`.
	private func run(arguments: [String]) async throws {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: try magickPath())
		process.arguments = arguments

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

	// MARK: - processImage()

	/// Processes a single image using an ImageMagick argument list.
	/// - Returns: The URL of the successfully processed output image.
	func processImage(inputPath: URL, outputPath: URL, commandArguments: [String]) async throws -> URL {
		guard FileManager.default.fileExists(atPath: inputPath.path) else {
			throw ImageMagickError.fileNotFound(inputPath)
		}

		var arguments = [inputPath.path]
		arguments.append(contentsOf: commandArguments)
		arguments.append(outputPath.path)

		try await run(arguments: arguments)
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

		var arguments = ["montage"]
		arguments.append(contentsOf: inputPaths.map(\.path))
		arguments.append(contentsOf: commandArguments)
		arguments.append(outputPath.path)

		try await run(arguments: arguments)
		return outputPath
	}

	// MARK: - process4Scroll()

	/// Slices a single image into several output files.
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

		for (args, output) in zip(commandArguments, outputPaths) {
			var arguments = [inputPath.path]
			arguments.append(contentsOf: args)
			arguments.append(output.path)
			try await run(arguments: arguments)
		}
		return outputPaths
	}
}

enum ImageMagickError: Error, LocalizedError {
	case fileNotFound(URL)
	case commandFailed(statusCode: Int32, message: String)
	case executableNotFound

	var errorDescription: String? {
		switch self {
			case .fileNotFound(let url): return "Input file not found: \(url.lastPathComponent)"
			case .commandFailed(let statusCode, let message):
				let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
				return "ImageMagick failed (\(statusCode)): \(trimmed.isEmpty ? "unknown error" : trimmed)"
			case .executableNotFound:
				return "ImageMagick 'magick' not found. Install it via Homebrew (e.g. /opt/homebrew/bin/magick)."
		}
	}
}
