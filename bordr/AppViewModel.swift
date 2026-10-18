//
//  AppViewModel.swift
//  bordr
//
//  Created by v on 7/22/25.
//

import AppKit // For NSImage
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Reads only an image's pixel dimensions from disk without decoding it fully.
func getImageDimensions(url: URL) -> CGSize? {
	guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

	let propertiesOptions = [kCGImageSourceShouldCache: false] as CFDictionary
	guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, propertiesOptions) as? [CFString: Any] else {
		return nil
	}

	let width = properties[kCGImagePropertyPixelWidth] as? CGFloat ?? 0
	let height = properties[kCGImagePropertyPixelHeight] as? CGFloat ?? 0

	return CGSize(width: width, height: height)
}

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

/// Safe indexing so preview code never crashes on an out-of-range index.
extension Array {
	subscript(safe index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}

enum AspectRatio: Identifiable, CaseIterable {
	// 1:1 : Square images.
	// 3:4 and 4:5 : Slightly taller images ideal for vertical posts.
	// 9:16 : Fullscreen vertical images
	// -- aspect ratios in 4k; provided by cc: unravel: https://www.unravel.com.au/aspect-ratio-cheat-sheet

	case square, twoThree, threeFour, fourFive, sixteenNine

	var dimensions: (Int, Int) {
		switch self {
			case .square: return (2048, 2048)
			case .twoThree: return (2160, 3240)
			case .threeFour: return (2160, 2880)
			case .fourFive: return (2304, 2880)
			case .sixteenNine: return (4096, 2304)
		}
	}

	var landVal: Double {
		switch self {
			case .square: return 1.0
			case .twoThree: return 2.0/3.0
			case .threeFour: return 3.0/4.0
			case .fourFive: return 4.0/5.0
			case .sixteenNine: return 9.0/16.0
		}
	}

	var portVal: Double {
		switch self {
			case .square: return 1.0
			case .twoThree: return 3.0/2.0
			case .threeFour: return 4.0/3.0
			case .fourFive: return 5.0/4.0
			case .sixteenNine: return 16.0/9.0
		}
	}

	var id: String {
		switch self {
			case .square: return "1:1"
			case .twoThree: return "2:3"
			case .threeFour: return "3:4"
			case .fourFive: return "4:5"
			case .sixteenNine: return "16:9"
		}
	}

	func getBorderedResolution() -> (Int, Int) {
		var width = self.dimensions.0 - 100
		var height = self.dimensions.1 - 100

		switch self {
			case .square:
				width = 1918 // -- keep consistent with older versions
				return (width, width)
			case .threeFour:
				width = width - (3 * 2) + 40
				height = height - (3 * 2) + 30
				return (width, height)
			case .twoThree, .fourFive, .sixteenNine:
				width -= (3 * 2)
				height -= (3 * 2)
				return (width, height)
		}
	}

	func invertDimensions(dimensions: (Int, Int)) -> (Int, Int) {
		return (dimensions.1, dimensions.0)
	}

	func resolution2String(dimensions: (Int, Int)) -> String {
		return "\(dimensions.0)x\(dimensions.1)"
	}
}

// MARK: - Montage configuration

struct Montage {
	var bgColor: Color = .white
	var isBordered: Bool = false

	var montageArgs: [String] {
		if isBordered {
			return [
				"-geometry", "'2048x2048+50+50>'",
				"-background", "'\(bgColor.toHexString())'",
				"-border", "4",
				"-bordercolor", "'\(borderColor.toHexString())'",
				"-quality", "92"
			]
		}

		return [
			"-geometry", "'2048x2048+50+50>'",
			"-background", "'\(bgColor.toHexString())'",
			"-quality", "92"
		]
	}

	private var borderColor: Color {
		switch bgColor {
			case Color.black: return Color.white
			case Color.white: return Color.black
			default: return Color.black
		}
	}
}

@Observable
class AppViewModel {
	var originalImages: [NSImage] = []
	var processedImages: [NSImage] = []
	var inputImageURLs: [URL] = []
	var currentAspectRatio: AspectRatio = .square
	var montage: Montage = Montage()
	var isLoading: Bool = false
	var errorMessage: String?

	/// Index shared by the original and processed previews. Reads are clamped in
	/// `currentOriginalImage`/`currentProcessedImage` and every writer clamps it;
	/// a `didSet` clamp here self-assigns and recurses to a stack overflow under @Observable.
	var currentImageIndex: Int = 0

	private let imageMagickProcessor = ImageMagickProcessor()

	// MARK: - Derived state

	var hasImages: Bool { !originalImages.isEmpty }
	var hasProcessedImages: Bool { !processedImages.isEmpty }
	var imageCount: Int { max(originalImages.count, processedImages.count) }

	var originalTitle: String { originalImages.count > 1 ? "Original Images" : "Original Image" }
	var processedTitle: String { processedImages.count > 1 ? "Processed Images" : "Processed Image" }

	/// The original image currently shown; clamped to the last source when the
	/// processed list is longer (e.g. a contact sheet added an extra output).
	var currentOriginalImage: NSImage? {
		guard !originalImages.isEmpty else { return nil }
		return originalImages[min(currentImageIndex, originalImages.count - 1)]
	}

	/// The processed image currently shown, clamped to the last output.
	var currentProcessedImage: NSImage? {
		guard !processedImages.isEmpty else { return nil }
		return processedImages[min(currentImageIndex, processedImages.count - 1)]
	}

	// MARK: - Loading images

	private func runOpenPanel() -> [URL] {
		let openPanel = NSOpenPanel()
		openPanel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
		openPanel.allowsMultipleSelection = true
		openPanel.canChooseDirectories = false
		openPanel.canChooseFiles = true
		return openPanel.runModal() == .OK ? openPanel.urls : []
	}

	/// Replaces the current selection with images chosen from an open panel.
	func selectImages() {
		let urls = runOpenPanel()
		guard !urls.isEmpty else { return }
		load(urls: urls, replacing: true)
	}

	/// Appends images chosen from an open panel to the current selection.
	func addImages() {
		let urls = runOpenPanel()
		guard !urls.isEmpty else { return }
		load(urls: urls, replacing: false)
	}

	/// Appends dropped image URLs to the current selection.
	func addImages(urls: [URL]) {
		guard !urls.isEmpty else { return }
		load(urls: urls, replacing: false)
	}

	private func load(urls: [URL], replacing: Bool) {
		errorMessage = nil

		var merged = replacing ? urls : inputImageURLs + urls

		// De-duplicate by canonical path, then order naturally by filename.
		var seen = Set<String>()
		merged = merged.filter { seen.insert($0.standardizedFileURL.path).inserted }
		merged.sort {
			$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
		}

		var images: [NSImage] = []
		var validURLs: [URL] = []
		for url in merged {
			if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
				images.append(image)
				validURLs.append(url)
			} else {
				errorMessage = "Could not load image: \(url.lastPathComponent)"
			}
		}

		inputImageURLs = validURLs
		originalImages = images
		if replacing { processedImages = [] }
		currentImageIndex = 0
	}

	// MARK: - Removing / reordering

	func removeImage(at index: Int) {
		guard originalImages.indices.contains(index) else { return }
		originalImages.remove(at: index)
		inputImageURLs.remove(at: index)
		if processedImages.indices.contains(index) {
			processedImages.remove(at: index)
		}
		if currentImageIndex > max(imageCount - 1, 0) {
			currentImageIndex = max(imageCount - 1, 0)
		}
	}

	func removeImages(at offsets: IndexSet) {
		for index in offsets.sorted(by: >) {
			removeImage(at: index)
		}
	}

	func moveImages(from source: IndexSet, to destination: Int) {
		inputImageURLs.move(fromOffsets: source, toOffset: destination)
		originalImages.move(fromOffsets: source, toOffset: destination)
	}

	func clearImages() {
		originalImages = []
		processedImages = []
		inputImageURLs = []
		currentImageIndex = 0
		errorMessage = nil
	}

	// MARK: - Navigation

	/// Moves to the previous image, wrapping from the first to the last.
	func selectPrevious() {
		guard imageCount > 0 else { return }
		currentImageIndex = currentImageIndex <= 0 ? imageCount - 1 : currentImageIndex - 1
	}

	/// Moves to the next image, wrapping from the last to the first.
	func selectNext() {
		guard imageCount > 0 else { return }
		currentImageIndex = currentImageIndex >= imageCount - 1 ? 0 : currentImageIndex + 1
	}

	// MARK: - Output paths

	private func generateOutputURL(url: URL) -> URL {
		let base = url.deletingPathExtension()
		return base.deletingLastPathComponent()
			.appendingPathComponent(base.lastPathComponent + "_processed.jpg")
	}

	private func generateOutputURLs4Scroll(url: URL, indx: Int) -> URL {
		let base = url.deletingPathExtension()
		return base.deletingLastPathComponent()
			.appendingPathComponent("\(base.lastPathComponent)_\(indx).jpg")
	}

	private func generateOutputURLsForCollage(urls: [URL]) -> URL? {
		guard let first = urls.first, let last = urls.last else { return nil }
		let name = first.deletingPathExtension().lastPathComponent
			+ "-"
			+ last.deletingPathExtension().lastPathComponent
			+ "__collage.jpg"
		return first.deletingLastPathComponent().appendingPathComponent(name)
	}

	// MARK: - ImageMagick argument builders

	private func processSelectedImagesArgs() -> [String] {
		return [
			"-resize", "'\(currentAspectRatio.resolution2String(dimensions: currentAspectRatio.getBorderedResolution()))>'",
			"-background", "white",
			"-bordercolor", "black",
			"-border", currentAspectRatio == AspectRatio.square ? "4" : "3",
			"-gravity", "center",
			"-extent", "'\(currentAspectRatio.resolution2String(dimensions: currentAspectRatio.dimensions))'",
			"-quality", "92"
		]
	}

	private func calculateImageSplits(imageDimensions: CGSize) -> Int {
		// portrait
		let splits: Double = Double(imageDimensions.width / (imageDimensions.height / currentAspectRatio.portVal))
		return Int(splits.rounded(.toNearestOrAwayFromZero))
	}

	private func imagemagickScrollArgs(image: URL) -> [[String]] {
		guard let dimensions = getImageDimensions(url: image) else { return [] }
		let splits = calculateImageSplits(imageDimensions: dimensions)
		guard splits >= 1 else { return [] }

		let width = Int(dimensions.width) / splits
		let resize = currentAspectRatio.resolution2String(dimensions: currentAspectRatio.dimensions)

		return (0..<splits).map { i in
			[
				"-gravity", "west",
				"-crop", "'\(width)x\(Int(dimensions.height))>+\(width * i)+0'",
				"-resize", "'\(resize)'",
				"-quality", "92"
			]
		}
	}

	private func scrollOutputURLs(image: URL) -> [URL] {
		guard let dimensions = getImageDimensions(url: image) else { return [] }
		let splits = calculateImageSplits(imageDimensions: dimensions)
		guard splits >= 1 else { return [] }
		return (1...splits).map { generateOutputURLs4Scroll(url: image, indx: $0) }
	}

	// MARK: - Processing

	/// Resizes every selected image and places it on the current aspect-ratio canvas.
	func processSelectedImages() {
		guard !inputImageURLs.isEmpty else { return }

		isLoading = true
		errorMessage = nil
		processedImages = []
		currentImageIndex = 0

		Task {
			let urls = await processSelectedImagesURLs().sorted {
				$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
			}

			await MainActor.run {
				for url in urls {
					if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
						processedImages.append(image)
					} else {
						errorMessage = "Could not load processed image: \(url.lastPathComponent)"
					}
				}
				isLoading = false
			}
		}
	}

	private func processSelectedImagesURLs() async -> [URL] {
		await withTaskGroup(of: URL?.self) { group in
			for url in inputImageURLs {
				group.addTask {
					do {
						return try await self.imageMagickProcessor.processImage(
							inputPath: url,
							outputPath: self.generateOutputURL(url: url),
							commandArguments: self.processSelectedImagesArgs()
						)
					} catch {
						await MainActor.run {
							self.errorMessage = "Processing failed: \(error.localizedDescription)"
						}
						return nil
					}
				}
			}

			var processedImageURLs: [URL] = []
			for await fileURL in group {
				if let fileURL { processedImageURLs.append(fileURL) }
			}
			return processedImageURLs
		}
	}

	/// Builds a single contact sheet from all selected images.
	func processSelectedImagesAsCollage(montage: Montage) {
		guard !inputImageURLs.isEmpty else { return }

		isLoading = true
		errorMessage = nil

		let outputURL = generateOutputURLsForCollage(urls: inputImageURLs)
			?? generateOutputURL(url: inputImageURLs.first!)

		Task {
			do {
				let processedFileURL = try await imageMagickProcessor.processCollage(
					inputPaths: inputImageURLs,
					outputPath: outputURL,
					commandArguments: montage.montageArgs
				)

				await MainActor.run {
					if let processedData = try? Data(contentsOf: processedFileURL),
					   let image = NSImage(data: processedData) {
						processedImages.append(image)
						currentImageIndex = processedImages.count - 1
					} else {
						errorMessage = "Failed to load processed image from disk."
					}
					isLoading = false
				}
			} catch {
				await MainActor.run {
					errorMessage = "Processing failed: \(error.localizedDescription)"
					isLoading = false
				}
			}
		}
	}

	/// Splits the current image into swipable halves sized to the current ratio.
	func processSelectedImageForScroll() {
		guard let image = inputImageURLs[safe: currentImageIndex] ?? inputImageURLs.first else {
			errorMessage = "Select an image first."
			return
		}

		let arguments = imagemagickScrollArgs(image: image)
		let outputs = scrollOutputURLs(image: image)
		guard !arguments.isEmpty, arguments.count == outputs.count else {
			errorMessage = "Could not determine how to split this image."
			return
		}

		isLoading = true
		errorMessage = nil

		Task {
			do {
				let urls = try await imageMagickProcessor.process4Scroll(
					inputPath: image,
					outputPaths: outputs,
					commandArguments: arguments
				)

				await MainActor.run {
					processedImages = []
					for url in urls {
						if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
							processedImages.append(img)
						}
					}
					isLoading = false
				}
			} catch {
				await MainActor.run {
					errorMessage = "Processing failed: \(error.localizedDescription)"
					isLoading = false
				}
			}
		}
	}
}
