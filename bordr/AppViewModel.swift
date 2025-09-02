//
//  AppViewModel.swift
//  bordr
//
//  Created by v on 7/22/25.
//

import AppKit // For NSImage
import SwiftUI

class AppViewModel: ObservableObject {
	@Published var originalImages: [NSImage?] = []
	@Published var processedImages: [NSImage?] = []
	@Published var isLoading: Bool = false
	@Published var isAppending: Bool = false
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
	
	private let imagemagickXHSArgs: [[String]] = [
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
	func processSelectedImagesAsCollage() {
		self.isLoading = true
		self.errorMessage = nil // Clear previous error
 
		Task { // Run the async operation in a Task
			do {
				let processedFileURL = try await imageMagickProcessor.processCollage(
					inputPaths: inputImageURLs,
					outputPath: generateOutputURLsForCollage(urls: inputImageURLs) ?? generateOutputURL(url: inputImageURLs.first!),
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
	
	// MARK: processSelectedImageForXHS
	func processSelectedImageForXHS() {
		self.isLoading = true
		self.errorMessage = nil // Clear previous error
 
		Task { // Run the async operation in a Task
			do {
				let processedFileURLs = try await imageMagickProcessor.processForXHS(
					inputPaths: inputImageURLs,
					outputPaths: generateOutputURLsForXHS(urls: inputImageURLs),
					commandArguments: imagemagickXHSArgs
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
							commandArguments: self.imagemagickArgs
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
