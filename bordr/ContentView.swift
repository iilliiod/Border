//
//  ContentView.swift
//  bordr
//
//  Created by v on 7/21/25.
//

import SwiftUI
import AppKit // For NSImage and NSOpenPanel/NSSavePanel

struct ContentView: View {
	let viewModel = AppViewModel()
	@State private var currentImageIndex: Int = 0
	
	// MARK: - Content View Body
	var body: some View {
		VStack {
			Spacer()
			
			HeaderView()
			
			Spacer()
			
			HStack {
				OriginalImagesView(currentImageIndex: $currentImageIndex)
					.padding()
				
				ProcessedImagesView(currentImageIndex: $currentImageIndex)
					.padding()
				
			}
			
			NavigationControlsView(currentImageIndex: $currentImageIndex)
				.padding()
			
		}
		.environmentObject(viewModel)
		.frame(minWidth: 600, minHeight: 400) // Set initial window size
		.navigationTitle("bordr") // Sets window title in macOS
	}
}


// MARK: - Header View Body
struct HeaderView: View {
	@EnvironmentObject var viewModel: AppViewModel
	
	var body: some View {
		HStack {
			Button("Select Image") {
				viewModel.selectImage()
			}
			.padding(.horizontal)

			Button("Process Image") {
				viewModel.processSelectedImages()
			}
			.disabled(viewModel.originalImages.isEmpty || viewModel.isLoading)
			.padding(.horizontal)

			Button("Collagify") {
				viewModel.processSelectedImagesAsCollage()
			}
			.disabled(viewModel.originalImages.isEmpty)
			.padding(.horizontal)
		}
		.padding(.bottom)
		
		if viewModel.isLoading {
			ProgressView("Processing...")
				.padding()
		} else if let errorMessage = viewModel.errorMessage {
			Text(errorMessage)
				.foregroundColor(.red)
				.padding()
		}
	}
}

// MARK: - Original Images View Body
struct OriginalImagesView: View {
	@EnvironmentObject var viewModel: AppViewModel
	@Binding var currentImageIndex: Int

	var body: some View {
		VStack {
			Text("Original Image")
				.font(.headline)
			
			if !viewModel.originalImages.isEmpty {
				
				Image(nsImage: viewModel.originalImages[currentImageIndex <= viewModel.originalImages.count - 1 ? currentImageIndex : viewModel.originalImages.count - 1]!)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(maxWidth: 400, maxHeight: 400)
					.border(Color.gray, width: 1)
					.padding(.horizontal) // Add some padding around the carousel
			} else {
				Text("No original image selected")
					.frame(width: 400, height: 400)
					.border(Color.gray, width: 1)
					.foregroundColor(.secondary)
			}
		}
	}
}

// MARK: - Processed Images View Body
struct ProcessedImagesView: View {
	@EnvironmentObject var viewModel: AppViewModel
	@Binding var currentImageIndex: Int
	
	var body: some View {
		VStack {
			Text("Processed Image")
				.font(.headline)
			
			if !viewModel.processedImages.isEmpty {
				Image(nsImage: viewModel.processedImages[currentImageIndex]!)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(maxWidth: 400, maxHeight: 400)
					.border(Color.gray, width: 1)
					.padding(.horizontal)
					.id(currentImageIndex)

			} else {
				Text("No processed image yet")
					.frame(width: 400, height: 400)
					.border(Color.gray, width: 1)
					.foregroundColor(.secondary)
			}
		}
	}
}

struct NavigationControlsView: View {
	@EnvironmentObject var viewModel: AppViewModel
	@Binding var currentImageIndex: Int
	
	func goPrevious() {
		if currentImageIndex > 0 {
			currentImageIndex -= 1
		}
	}
	
	func goNext() {
		if viewModel.processedImages.isEmpty {
			if currentImageIndex < viewModel.originalImages.count - 1 {
				currentImageIndex += 1
			}
		} else if currentImageIndex < viewModel.processedImages.count - 1 {
			currentImageIndex += 1
		}
	}
	var body: some View {
		// Navigation Controls
		HStack {
			if !viewModel.originalImages.isEmpty {
				Spacer()
				
				Button(action: goPrevious) {
					Image(systemName: "chevron.left")
				}
				.disabled(currentImageIndex == 0)
				
				Text("\(currentImageIndex + 1) / \(viewModel.processedImages.isEmpty ? viewModel.originalImages.count : viewModel.processedImages.count)")
				
				Button(action: goNext) {
					Image(systemName: "chevron.right")
				}
				.disabled(viewModel.processedImages.isEmpty ? currentImageIndex == viewModel.originalImages.count - 1 : currentImageIndex == viewModel.processedImages.count - 1)
				
				Spacer()
			}
		}
	}
}

#Preview {
    ContentView()
}
