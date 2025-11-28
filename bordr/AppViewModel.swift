//
//  AppViewModel.swift
//  bordr
//
//  Created by v on 7/22/25.
//

import AppKit // For NSImage
import SwiftUI

extension Color {
	func toHexString() -> String {
		let uiColor = NSColor(self)
		var r: CGFloat = 0
		var g: CGFloat = 0
		var b: CGFloat = 0
		var a: CGFloat = 0

		uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

		let rgb: Int = (Int)(r * 255) << 16 | (Int)(g * 255) << 8 | (Int)(b * 255) << 0
		return String(format: "#%06x", rgb)
	}
}

enum AspectRatio: Identifiable, CaseIterable {
	case square, threeFour
	var id: String {
		switch self {
			case .square:
				return "1:1"
			case .threeFour:
				return "3:4"
		}
	}
}

class Montage {
	var bgColor: Color = .white
	var isBordered: Bool = false
	var montageArgs: [String] {
		if self.isBordered {
			return [
				"-geometry", "'2048x2048+50+50>'",
				"-background", "'\(self.bgColor.toHexString())'",
				"-border", "4",
				"-bordercolor", "'\(self.getBorderColor().toHexString())'",
				"-quality", "92"
			]
		}
		
		return [
			"-geometry", "'2048x2048+50+50>'",
			"-background", "'\(self.bgColor.toHexString())'",
			"-quality", "92"
		]
	}
	
	func getBgColor() -> Color {
		return Color(self.bgColor)
	}
	
	private func getBorderColor() -> Color {
		switch self.bgColor {
			case Color.black:
				return Color.white
			case Color.white:
				return Color.black
			default:
				return Color.black
		}
	}
	
}

@Observable class AppViewModel {
	var originalImages: [NSImage?] = []
	var processedImages: [NSImage?] = []
	var currentAspectRatio: AspectRatio = .square
	var montage: Montage = Montage()
	var isLoading: Bool = false
	var isAppending: Bool = false
	var errorMessage: String?
	var inputImageURLs: [URL] = [] // Keep track of the selected input file URL
	var currentImageIndex: Int = 0 {
		didSet {
			// Optional: Ensure index stays within bounds if it's manipulated externally
			if originalImages.isEmpty {
				currentImageIndex = 0
			} else if currentImageIndex >= originalImages.count {
				currentImageIndex = originalImages.count - 1
			} else if currentImageIndex < 0 {
				currentImageIndex = 0
			}
		}
	}
	
	private func imageMagickArgs() -> [String] {
		switch self.currentAspectRatio {
			case .square:
				return [
					"-resize", "'1918x1918>'", // Resize to fit *within* the padded area (2048 - (50*2) - (4*2))
					"-background", "white",
					"-bordercolor", "black",
					"-border", "4",
					"-gravity", "center",
					"-extent", "'2048x2048'",
					"-quality", "92"
				]
			case .threeFour:
				return [
					"-resize", "'1374x1844>'",
					"-background", "white",
					"-bordercolor", "black",
					"-border", "3",
					"-gravity", "center",
					"-extent", "'1440x1920'",
					"-quality", "92"
				]
		}
	}
	
//	private let imagemagickMontageArgs: [String] = [
//		"-geometry", "'2048x2048+50+50>'",
//		"-background", "black",
//		"-border", "4",
//		"-bordercolor", "white",
//		"-quality", "92"
//	]
	
	private func imagemagickXHSArgs() -> [[String]] {
		switch self.currentAspectRatio {
			case .square:
				return [
					[
						"-resize", "'4092x4042'",
						"-bordercolor", "black",
						"-border", "4",
						"-gravity", "west",
						"-crop", "'50x100%+0+0'",
						"-resize", "'4092x4042'",
						"-background", "white",
						"-gravity", "east",
						"-extent", "'4096x4096'",
						"-quality", "92"
					],
					[
						"-resize", "'4092x4042'",
						"-bordercolor", "black",
						"-border", "4",
						"-gravity", "east",
						"-crop", "'50x100%+0+0'",
						"-resize", "'4092x4042'",
						"-background", "white",
						"-gravity", "west",
						"-extent", "'4096x4096'",
						"-quality", "92"
					],
				]
			case .threeFour:
				return [
					[
						"-gravity", "west",
						"-crop", "'50x100%+0+0'",
						"-resize", "'1440x1920'",
						"-quality", "92"
					],
					[
						"-gravity", "east",
						"-crop", "'50x100%+0+0'",
						"-resize", "'1440x1920'",
						"-quality", "92"
					],
				]
		}
	}
	
	private let imageMagickProcessor = ImageMagickProcessor()
	
	// MARK: selectImage()
	func selectImage() {
		let openPanel = NSOpenPanel()
		openPanel.allowedContentTypes = [.png, .jpeg, .tiff] // Common image types
		openPanel.allowsMultipleSelection = true
		openPanel.canChooseDirectories = false // todo: add support for directories (operation on all images in directory)
		openPanel.canChooseFiles = true
		
		if openPanel.runModal() == .OK {
			if !self.isAppending {
				self.inputImageURLs = openPanel.urls.sorted {
					$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
				}
			} else {
				let allURLs = Set(self.inputImageURLs + openPanel.urls)
				self.inputImageURLs = allURLs.sorted {
					$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
				}
			}
			
			self.originalImages = []
			
			if self.isAppending == false {
				self.processedImages = []
			}
			
			self.errorMessage = nil

			self.inputImageURLs.forEach { img in
				do {
					let imgData = try Data(contentsOf: img)
					self.originalImages.append(NSImage(data: imgData))
					print("image url: \(img)")
				} catch {
					self.errorMessage = "Could not load image: \(error.localizedDescription)"
				}
			}
			
			self.isAppending = false
		}
	}
	
	private func generateOutputURL(url: URL) -> URL {
		let baseURL = url.deletingLastPathComponent()
		let outputFileName = "\(url.lastPathComponent.replacingOccurrences(of: ".jpg", with: "_"))_processed.jpg"
		return baseURL.appendingPathComponent(outputFileName, conformingTo: .jpeg)
	}
	
	private func generateOutputURLsForXHS(urls: [URL]) -> [URL] {
		var outputURL: [URL] = []
		
		for url in urls {
			let leftOutputFileName = "\(url.lastPathComponent.replacingOccurrences(of: ".jpg", with: "_l")).jpg"
			// let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
			let baseURL = url.deletingLastPathComponent()
			outputURL.append(baseURL.appendingPathComponent(leftOutputFileName, conformingTo: .jpeg))
			
			let rightOutputFileName = "\(url.lastPathComponent.replacingOccurrences(of: ".jpg", with: "_r")).jpg"
			outputURL.append(baseURL.appendingPathComponent(rightOutputFileName, conformingTo: .jpeg))
		}

		return outputURL
	}
	
	private func generateOutputURLsForCollage(urls: [URL]) -> URL? {
		guard urls.first?.isFileURL != nil, urls.last?.isFileURL != nil else {
			return nil
		}
		
		let baseURL = urls.first!.deletingLastPathComponent()
		let outputFileName = "\(urls.first!.lastPathComponent.replacingOccurrences(of: ".jpg", with: "-").appending("\(urls.last!.lastPathComponent.replacingOccurrences(of: ".jpg", with: "__collage"))")).jpg"
		
		return baseURL.appendingPathComponent(outputFileName, conformingTo: .jpeg)
	}

	// MARK: processSelectedImagesAsCollage()
	func processSelectedImagesAsCollage(montage: Montage) {
		self.isLoading = true
		self.errorMessage = nil // Clear previous error
 
		Task { // Run the async operation in a Task
			do {
				let processedFileURL = try await imageMagickProcessor.processCollage(
					inputPaths: inputImageURLs,
					outputPath: generateOutputURLsForCollage(urls: inputImageURLs) ?? generateOutputURL(url: inputImageURLs.first!),
					commandArguments: montage.montageArgs
				)
				
				// Update UI on the main actor
				await MainActor.run {
					// might be off here
					if let processedData = try? Data(contentsOf: processedFileURL),
					   let image = NSImage(data: processedData) {
						self.processedImages.append(image)
					} else {
						self.errorMessage = "Failed to load processed image from disk."
					}
					self.isLoading = false
				}
			} catch {
				// Update UI on the main actor
				await MainActor.run {
					
					print("output urls: \(inputImageURLs)")
					
					self.errorMessage = "Processing failed: \(error.localizedDescription)"
					self.isLoading = false
				}
			}
		}
	}
	
	// MARK: processSelectedImageForXHS
	func processSelectedImageForXHS() {
		self.isLoading = true
		self.errorMessage = nil // Clear previous error
 
		Task { // Run the async operation in a Task
			do {
				let processedFileURLs = try await imageMagickProcessor.processForXHS(
					inputPaths: inputImageURLs,
					outputPaths: generateOutputURLsForXHS(urls: inputImageURLs),
					commandArguments: imagemagickXHSArgs()
				)
				
				// Update UI on the main actor
				await MainActor.run {
					// might be off here
					guard !processedFileURLs.isEmpty else {
						self.isLoading = false
						self.errorMessage = "Failed to load processed image from disk."
						return
					}
					
					processedFileURLs.forEach { url in
						if let data = try? Data(contentsOf: url),
						   let image = NSImage(data: data) {
							self.processedImages.append(image)
						}
					}
					self.isLoading = false
				}
			} catch {
				// Update UI on the main actor
				await MainActor.run {
					
					print("output urls: \(inputImageURLs)")
					
					self.errorMessage = "Processing failed: \(error.localizedDescription)"
					self.isLoading = false
				}
			}
		}
	}

	
	// MARK: processSelectedImagesURLs
	private func processSelectedImagesURLs() async -> [URL] {
		var processedImageURLs: [URL] = []
		
		await withTaskGroup(of: URL?.self) { group in
			for url in self.inputImageURLs {
				group.addTask {
					do {
						let processedFileURL = try await self.imageMagickProcessor.processImage(
							inputPath: url,
							outputPath: self.generateOutputURL(url: url),
							commandArguments: self.imageMagickArgs()
						)
						return processedFileURL
					} catch ImageMagickError.fileAlreadyExists {
						return self.generateOutputURL(url: url)
					} catch {
						// Update UI on the main actor
						await MainActor.run {
							
							print("output url: \(url)")
							
							self.errorMessage = "Processing failed: \(error.localizedDescription)"
							self.isLoading = false
						}
					}
					return nil
				}
			}
			
			// Use for await to collect the results from all tasks as they complete
			for await fileURL in group {
				if let fileURL = fileURL {
					processedImageURLs.append(fileURL)
				}
			}
		}
		
		return processedImageURLs
	}
	
	// MARK: processSelectedImages()
	func processSelectedImages() {
		self.isLoading = true
		self.errorMessage = nil // Clear previous error
		self.processedImages = [] // Clear previous processed images
		self.currentImageIndex = 0 // Reset index
		
		Task {
			let sortedProcessedImageURLs = await processSelectedImagesURLs().sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending
			}
			
			await MainActor.run {
				sortedProcessedImageURLs.forEach { img in
					do {
						let imgData = try Data(contentsOf: img)
						self.processedImages.append(NSImage(data: imgData))
						print("image url: \(img)")
					} catch {
						self.errorMessage = "Could not load image: \(error.localizedDescription)"
					}
				}
				self.isLoading = false
			}
		}
		
	}

	func saveProcessedImage() {
//		guard let processedImg = processedImage else {
//			self.errorMessage = "No processed image to save."
//			return
//		}
//
//		let savePanel = NSSavePanel()
//		savePanel.canCreateDirectories = true
//		savePanel.prompt = "Save Processed Image"
//		savePanel.nameFieldStringValue = inputImageURL?.lastPathComponent ?? "bordr_"
//
//		if savePanel.runModal() == .OK {
//			if let url = savePanel.url {
//				do {
//					// Convert NSImage to Data (e.g., PNG representation)
//					guard let tiffData = processedImg.tiffRepresentation,
//						  let bitmapImageRep = NSBitmapImageRep(data: tiffData),
//						  let jpgData = bitmapImageRep.representation(using: .jpeg, properties: [:]) else {
//						throw NSError(domain: "ImageConversion", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not convert image to JPEG data."])
//					}
//					
//					try jpgData.write(to: url)
//					print("Image saved successfully to: \(url.path)")
//				} catch {
//					self.errorMessage = "Failed to save image: \(error.localizedDescription)"
//				}
//			}
//		}
	}
}
