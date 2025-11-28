//
//  ContentView.swift
//  bordr
//
//  Created by v on 7/21/25.
//

import SwiftUI
import AppKit // For NSImage and NSOpenPanel/NSSavePanel

struct ContentView: View {
	@State private var viewModel = AppViewModel()
	@State private var currentImageIndex: Int = 0
	
	// MARK: - Content View Body
	var body: some View {
		VStack {
			HeaderView(viewModel: viewModel)
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
		.environment(viewModel)
		.frame(minWidth: 600, minHeight: 600) // Set initial window size
		.navigationTitle("bordr") // Sets window title in macOS
		.padding()
	}
}


// MARK: - Header View Body
struct HeaderView: View {
	@Bindable var viewModel: AppViewModel
	@State private var isMontagePopover: Bool = false
	@State private var isBordered: Bool = false

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
				
				Button(viewModel.originalImages.count > 1 ? "Process Images" : "Process Image") {
					viewModel.processSelectedImages()
				}
				.disabled(viewModel.originalImages.isEmpty || viewModel.isLoading)
				
				Picker(selection: $viewModel.currentAspectRatio) {
					ForEach(AspectRatio.allCases) { ratio in
						Text(ratio.id)
							.tag(ratio)
					}
				} label: {}
				.pickerStyle(.segmented)
				.frame(maxWidth: 70)
				.disabled(viewModel.originalImages.isEmpty || viewModel.isLoading)

				Button("Collagify") {
					isMontagePopover.toggle()
				}
				.disabled(viewModel.originalImages.count < 2)
				.sheet(isPresented: $isMontagePopover, content: {
					VStack(alignment: .leading) {
						ColorPicker("BG Color", selection: $viewModel.montage.bgColor)
						
						Toggle("Individual Image Border", isOn: $isBordered)
							.toggleStyle(.switch)
						
						Spacer()
						
						HStack {
							Button("Cancel", role: .cancel) {
								isMontagePopover = false
							}
							.foregroundStyle(.red)
							
							Button("Generate") {
								isMontagePopover = false
								viewModel.montage.isBordered = isBordered
								viewModel.processSelectedImagesAsCollage(montage: viewModel.montage)
							}
						}
						.padding()
					}
					.padding()
				})
				.onSubmit {
					print("Submitted.")
				}
				
				
				Button("Process for XHS") {
					viewModel.currentAspectRatio = AspectRatio.threeFour
					
					viewModel.processSelectedImages()
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
	@Environment(AppViewModel.self) private var viewModel: AppViewModel
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
	@Environment(AppViewModel.self) private var viewModel: AppViewModel
	@Binding var currentImageIndex: Int
	
	var body: some View {
		VStack {
			Text(viewModel.originalImages.count > 1 ? "Processed Images" : "Processed Image")
				.font(.headline)
			
			if !viewModel.processedImages.isEmpty {
				Image(nsImage: viewModel.processedImages[min(currentImageIndex, viewModel.processedImages.count - 1)]!)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: viewModel.currentAspectRatio == AspectRatio.threeFour ? 300 : 400, height: 400)
					.border(Color.gray, width: 1)
//					.id(currentImageIndex)
					.id(viewModel.processedImages)

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
	@Environment(AppViewModel.self) private var viewModel: AppViewModel
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
					.onChange(of: viewModel.originalImages) {
						currentImageIndex = 0
					}
				
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
