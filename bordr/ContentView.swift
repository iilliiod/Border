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
			HeaderView()
				.padding()
			
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
		.frame(minWidth: 600, minHeight: 600) // Set initial window size
		.navigationTitle("bordr") // Sets window title in macOS
		.padding()
	}
}


// MARK: - Header View Body
struct HeaderView: View {
	@EnvironmentObject var viewModel: AppViewModel
	
	var body: some View {
		HStack(spacing: 10) {
			Button("Select Images") {
				viewModel.selectImage()
			}

			if !viewModel.originalImages.isEmpty {
				Button {
					viewModel.isAppending = true
					viewModel.selectImage()
					
					if !viewModel.processedImages.isEmpty {
						viewModel.processSelectedImages()
					}
				} label: {
					Image(systemName: "plus")
				}
				.disabled(viewModel.originalImages.isEmpty || viewModel.isLoading)
				
				Button("Process Image") {
					viewModel.processSelectedImages()
				}
				.disabled(viewModel.originalImages.isEmpty || viewModel.isLoading)

				Button("Collagify") {
					viewModel.processSelectedImagesAsCollage()
				}
				.disabled(viewModel.originalImages.isEmpty)
				
				Button("Process for XHS") {
					viewModel.processSelectedImageForXHS()
				}
				.disabled(viewModel.originalImages.isEmpty)
			}

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
			Text(viewModel.originalImages.count > 1 ? "Original Images" : "Original Image")
				.font(.headline)
			
			if !viewModel.originalImages.isEmpty {
				Image(nsImage: viewModel.originalImages[currentImageIndex <= viewModel.originalImages.count - 1 ? currentImageIndex : viewModel.originalImages.count - 1]!)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 400, height: 400)
					.border(Color.gray, width: 1)
			} else {
				Text("No images selected yet")
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
			Text(viewModel.originalImages.count > 1 ? "Processed Images" : "Processed Image")
				.font(.headline)
			
			if !viewModel.processedImages.isEmpty {
				Image(nsImage: viewModel.processedImages[min(currentImageIndex, viewModel.processedImages.count - 1)]!)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 400, height: 400)
					.border(Color.gray, width: 1)
					.id(currentImageIndex)

			} else {
				Text("No images processed yet")
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
		if currentImageIndex < max(viewModel.originalImages.count - 1, viewModel.processedImages.count - 1) {
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
				
				Text("\(currentImageIndex + 1) / \(viewModel.processedImages.isEmpty ? viewModel.originalImages.count : max(viewModel.originalImages.count, viewModel.processedImages.count))")
				
				Button(action: goNext) {
					Image(systemName: "chevron.right")
				}
				.disabled(viewModel.processedImages.isEmpty ? currentImageIndex == viewModel.originalImages.count - 1 : currentImageIndex == max(viewModel.processedImages.count - 1, viewModel.originalImages.count - 1))
				
				Spacer()
			}
		}
	}
}

#Preview {
    ContentView()
}
