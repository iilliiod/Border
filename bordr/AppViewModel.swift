//
//  AppViewModel.swift
//  bordr
//
//  Created by v on 7/22/25.
//

import AppKit // For NSImage
import SwiftUI // For @Published

class AppViewModel: ObservableObject {
	@Published var originalImages: [NSImage?] = []
	@Published var processedImages: [NSImage?] = []
	@Published var isLoading: Bool = false
	@Published var errorMessage: String?
	@Published var inputImageURLs: [URL] = [] // Keep track of the selected input file URL
	@Published var currentImageIndex: Int = 0 {
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

	private let imagemagickArgs: [String] = [
		"-resize", "'1918x1918>'",
		"-background", "white",
		"-bordercolor", "black",
		"-border", "4",
		"-gravity", "center",
		"-extent", "'2048x2048'",
		"-quality", "92"
	]
	
	private let imagemagickMontageArgs: [String] = [
		"-geometry", "'2048x2048+50+50>'",
		"-background", "white",
		"-border", "4",
		"-bordercolor", "black",
		"-quality", "92"
	]
	
	private let imageMagickProcessor = ImageMagickProcessor()
	
	// MARK: selectImage()
	func selectImage() {
		let openPanel = NSOpenPanel()
		openPanel.allowedContentTypes = [.png, .jpeg, .tiff, .heic] // Common image types
		openPanel.allowsMultipleSelection = true
		openPanel.canChooseDirectories = false // todo: add support for directories (operation on all images in directory)
		openPanel.canChooseFiles = true
		
		if openPanel.runModal() == .OK {
			self.inputImageURLs = openPanel.urls
			self.originalImages = []
			self.processedImages = []
			self.errorMessage = nil
			
			openPanel.urls.forEach { img in
				do {
					let imgData = try Data(contentsOf: img)
					self.originalImages.append(NSImage(data: imgData))
					print("image url: \(img)")
				} catch {
					self.errorMessage = "Could not load image: \(error.localizedDescription)"
				}
			}
			self.currentImageIndex = 0
		}
	}
	
	func generateOutputURL(url: URL) -> URL {
		var outputURL: URL
		
		let outputFileName = "\(url.lastPathComponent.replacingOccurrences(of: ".jpg", with: "_"))_processed.jpg"
		// let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(outputFileName)
		let baseURL = url.deletingLastPathComponent()
		outputURL = baseURL.appendingPathComponent(outputFileName, conformingTo: .jpeg)
		
		return outputURL
	}
	
	// MARK: processSelectedImagesAsCollage()
	func processSelectedImagesAsCollage() {
		self.isLoading = true
		self.errorMessage = nil // Clear previous error

		Task { // Run the async operation in a Task
			do {
				let processedFileURL = try await imageMagickProcessor.processCollage(
					inputPaths: inputImageURLs,
					outputPath: inputImageURLs.first!.deletingLastPathComponent().appendingPathComponent("__collage", conformingTo: .jpeg),
					commandArguments: imagemagickMontageArgs
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

	
	// MARK: processSelectedImages()
	func processSelectedImages() {
		self.isLoading = true
		self.errorMessage = nil // Clear previous error

		inputImageURLs.forEach { url in
			Task { // Run the async operation in a Task
				do {
					let processedFileURL = try await imageMagickProcessor.processImage(
						inputPath: url,
						outputPath: generateOutputURL(url: url),
						commandArguments: imagemagickArgs
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
						
						print("output url: \(url)")
						
						self.errorMessage = "Processing failed: \(error.localizedDescription)"
						self.isLoading = false
					}
				}
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
