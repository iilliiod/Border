//
//  ImageMagickProcessor.swift
//  bordr
//
//  Created by v on 7/22/25.
//

import Foundation
import AppKit // Not strictly needed for the processor itself, but for NSImage if you return it directly

class ImageMagickProcessor {
	
	// MARK: processImage()
	/// Processes an image using an ImageMagick CLI command.
	/// - Parameters:
	///   - inputPath: The full path to the input image file.
	///   - outputPath: The full path where the processed image will be saved.
	///   - commandArguments: An array of strings representing the ImageMagick command arguments
	///                       (e.g., ["-resize", "1820x1820>", "-background", "white", ...])
	/// - Throws: `ImageMagickError` if the process fails.
	/// - Returns: The URL of the successfully processed output image.
	func processImage(inputPath: URL, outputPath: URL, commandArguments: [String]) async throws -> URL {
		
		// Check if the output fle exists
		guard !FileManager.default.fileExists(atPath: outputPath.path) else {
			throw ImageMagickError.fileAlreadyExists(outputPath)
		}
		
		// Ensure the input file exists
		guard FileManager.default.fileExists(atPath: inputPath.path) else {
			throw ImageMagickError.fileNotFound(inputPath)
		}
		
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/bash") // or "/bin/zsh"
		
		// Determine the actual magick path. Prioritize discovered, then common Homebrew paths.
		let actualMagickPath: String
		
		if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/magick") {
			actualMagickPath = "/opt/homebrew/bin/magick"
		} else if FileManager.default.fileExists(atPath: "/usr/local/bin/magick") {
			actualMagickPath = "/usr/local/bin/magick"
		} else {
			throw ImageMagickError.executableNotFound // Cannot find magick executable at all
		}
		
		// Construct the full ImageMagick command string, ensuring paths with spaces are quoted
		var commandParts: [String] = []
		commandParts.append(actualMagickPath.shellEscaped()) // Use shellEscaped for the executable itself
		commandParts.append(inputPath.path.shellEscaped()) // Input path must be escaped
		
		// Add existing arguments. Assume they are already properly formatted/quoted if needed
		commandParts.append(contentsOf: commandArguments)
		
		commandParts.append(outputPath.path.shellEscaped()) // Output path must be escaped
		
		let fullCommandString = commandParts.joined(separator: " ")
		
		// Pass the command string as an argument to the shell with -c ---
		process.arguments = ["-c", fullCommandString]
		
		// --- DEBUG PRINT: Log the full command executed by the shell ---
		print("DEBUG: Executing with shell: \(process.executableURL!.path) -c \"\(fullCommandString)\"")
		
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe // Capture both stdout and stderr for debugging

		return try await withCheckedThrowingContinuation { continuation in
			process.terminationHandler = { currentProcess in
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				let output = String(data: data, encoding: .utf8)

				if currentProcess.terminationStatus == 0 {
					// Success!
					print("DEBUG: ImageMagick command succeeded.")
					continuation.resume(returning: outputPath)
				} else {
					// Command failed
					let errorMessage = output ?? "Unknown error"
					
					// --- DEBUG PRINT: Log the full error output from ImageMagick ---
										print("DEBUG: ImageMagick command failed with status \(currentProcess.terminationStatus). Output:\n\(errorMessage)")
					
					continuation.resume(throwing: ImageMagickError.commandFailed(statusCode: currentProcess.terminationStatus, message: errorMessage))
				}
			}

			do {
				try process.run()
			} catch {
				print("DEBUG: Error running Process: \(error.localizedDescription)")
				continuation.resume(throwing: error)
			}
		}
	}
	
	// MARK: processCollage()
	func processCollage(inputPaths: [URL], outputPath: URL, commandArguments: [String]) async throws -> URL {
		// Ensure the input file exists
		try inputPaths.forEach { inputPath in
			guard FileManager.default.fileExists(atPath: inputPath.path) else {
				throw ImageMagickError.fileNotFound(inputPath)
			}
		}
		
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/bash") // or "/bin/zsh"
		
		// Determine the actual magick path. Prioritize discovered, then common Homebrew paths.
		let actualMagickPath: String
		
		if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/magick") {
			actualMagickPath = "/opt/homebrew/bin/magick"
		} else if FileManager.default.fileExists(atPath: "/usr/local/bin/magick") {
			actualMagickPath = "/usr/local/bin/magick"
		} else {
			throw ImageMagickError.executableNotFound // Cannot find magick executable at all
		}
		
		// Construct the full ImageMagick command string, ensuring paths with spaces are quoted
		var commandParts: [String] = []
		commandParts.append(actualMagickPath.shellEscaped()) // Use shellEscaped for the executable itself
		commandParts.append("montage")
		
		inputPaths.forEach { inputPath in
			commandParts.append(inputPath.path.shellEscaped())
		}
		
		// Add existing arguments. Assume they are already properly formatted/quoted if needed
		commandParts.append(contentsOf: commandArguments)
		
		commandParts.append(outputPath.path.shellEscaped()) // Output path must be escaped
		
		let fullCommandString = commandParts.joined(separator: " ")
		
		// Pass the command string as an argument to the shell with -c ---
		process.arguments = ["-c", fullCommandString]
		
		// --- DEBUG PRINT: Log the full command executed by the shell ---
		print("DEBUG: Executing with shell: \(process.executableURL!.path) -c \"\(fullCommandString)\"")
		
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe // Capture both stdout and stderr for debugging

		return try await withCheckedThrowingContinuation { continuation in
			process.terminationHandler = { currentProcess in
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				let output = String(data: data, encoding: .utf8)

				if currentProcess.terminationStatus == 0 {
					// Success!
					print("DEBUG: ImageMagick command succeeded.")
					continuation.resume(returning: outputPath)
				} else {
					// Command failed
					let errorMessage = output ?? "Unknown error"
					
					// --- DEBUG PRINT: Log the full error output from ImageMagick ---
										print("DEBUG: ImageMagick command failed with status \(currentProcess.terminationStatus). Output:\n\(errorMessage)")
					
					continuation.resume(throwing: ImageMagickError.commandFailed(statusCode: currentProcess.terminationStatus, message: errorMessage))
				}
			}

			do {
				try process.run()
			} catch {
				print("DEBUG: Error running Process: \(error.localizedDescription)")
				continuation.resume(throwing: error)
			}
		}

	}
}

enum ImageMagickError: Error, LocalizedError {
	case fileNotFound(URL)
	case fileAlreadyExists(URL)
	case commandFailed(statusCode: Int32, message: String)
	case executableNotFound // If magick can't be found at common paths

	var errorDescription: String? {
		switch self {
			case .fileNotFound(let url): return "Input file not found: \(url.lastPathComponent)"
			case .fileAlreadyExists(let url): return "Output file already exists: \(url.lastPathComponent)"
			case .commandFailed(let statusCode, let message): return "ImageMagick command failed with status \(statusCode): \(message)"
			case .executableNotFound: return "ImageMagick executable 'magick' not found. Please ensure it's installed (e.g., via Homebrew in /usr/local/bin/magick or /opt/homebrew/bin/magick)."
		}
	}
}

// --- Helper Extension for Shell Escaping ---
extension String {
	func shellEscaped() -> String {
		// If the string contains no special characters, return it as is.
		// This is a simplified check; a more robust one might be needed for very complex strings.
		guard self.rangeOfCharacter(from: CharacterSet(charactersIn: " \"'\\$!*?[]{}<>()`~#&|;")) != nil else {
			return self
		}
		// Enclose in single quotes and escape any single quotes within.
		return "'" + self.replacingOccurrences(of: "'", with: "'\\''") + "'"
	}
}
