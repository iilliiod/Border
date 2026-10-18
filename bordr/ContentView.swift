//
//  ContentView.swift
//  bordr
//
//  Created by v on 7/21/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
	@State private var viewModel = AppViewModel()
	@State private var columnVisibility: NavigationSplitViewVisibility = .all
	@State private var keyMonitor: Any?

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			ImageSidebar(viewModel: viewModel)
		} detail: {
			EditorView(viewModel: viewModel)
		}
		.navigationTitle("Bordr")
		.frame(minWidth: 960, minHeight: 640)
		.onAppear(perform: installArrowKeyMonitor)
		.onDisappear(perform: removeArrowKeyMonitor)
	}

	/// Left/right arrow keys step through images (with wrap-around).
	/// Handled at the window level so it works regardless of which view has focus,
	/// while ignoring panel/sheet key windows so dialogs keep normal arrow behavior.
	private func installArrowKeyMonitor() {
		guard keyMonitor == nil else { return }
		keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
			let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
			guard modifiers.isEmpty,
				  event.window === NSApp.mainWindow,
				  NSApp.mainWindow?.attachedSheet == nil,
				  viewModel.imageCount > 0 else { return event }

			switch event.keyCode {
				case 123: // left arrow
					viewModel.selectPrevious()
					return nil
				case 124: // right arrow
					viewModel.selectNext()
					return nil
				default:
					return event
			}
		}
	}

	private func removeArrowKeyMonitor() {
		if let keyMonitor {
			NSEvent.removeMonitor(keyMonitor)
			self.keyMonitor = nil
		}
	}
}

// MARK: - Sidebar

private struct ImageSidebar: View {
	@Bindable var viewModel: AppViewModel
	@State private var isDropTargeted = false

	private var selection: Binding<Int?> {
		Binding(
			get: { viewModel.originalImages.isEmpty ? nil : viewModel.currentImageIndex },
			set: { if let value = $0 { viewModel.currentImageIndex = value } }
		)
	}

	var body: some View {
		VStack(spacing: 0) {
			List(selection: selection) {
				Section("Input Images") {
					if viewModel.inputImageURLs.isEmpty {
						Text("No images yet")
							.foregroundStyle(.secondary)
					} else {
						ForEach(Array(viewModel.inputImageURLs.enumerated()), id: \.element) { index, url in
							SidebarRow(url: url, image: viewModel.originalImages[safe: index])
								.tag(index)
								.contextMenu {
									Button("Remove", role: .destructive) {
										viewModel.removeImage(at: index)
									}
								}
						}
						.onMove { viewModel.moveImages(from: $0, to: $1) }
						.onDelete { viewModel.removeImages(at: $0) }
					}
				}
			}
			.listStyle(.sidebar)

			Divider()

			VStack(spacing: 8) {
				Button {
					viewModel.selectImages()
				} label: {
					Label("Select Images", systemImage: "photo.badge.plus")
						.frame(maxWidth: .infinity)
				}
				.controlSize(.large)
				.buttonStyle(.borderedProminent)

				Button {
					viewModel.addImages()
				} label: {
					Label("Add to Selection", systemImage: "plus")
						.frame(maxWidth: .infinity)
				}
				.controlSize(.large)
				.disabled(!viewModel.hasImages)

				if viewModel.hasImages {
					Button(role: .destructive) {
						viewModel.clearImages()
					} label: {
						Label("Clear All", systemImage: "trash")
							.frame(maxWidth: .infinity)
					}
					.controlSize(.large)
				}
			}
			.padding(12)
		}
		.navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
		.dropDestination(for: URL.self) { urls, _ in
			viewModel.addImages(urls: urls)
			return true
		} isTargeted: { isDropTargeted = $0 }
		.overlay {
			if isDropTargeted {
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7]))
					.padding(6)
					.allowsHitTesting(false)
			}
		}
	}
}

private struct SidebarRow: View {
	let url: URL
	let image: NSImage?

	var body: some View {
		HStack(spacing: 10) {
			Group {
				if let image {
					Image(nsImage: image)
						.resizable()
						.scaledToFill()
				} else {
					Image(systemName: "photo")
						.foregroundStyle(.secondary)
				}
			}
			.frame(width: 40, height: 40)
			.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.strokeBorder(Color(nsColor: .separatorColor))
			)

			Text(url.lastPathComponent)
				.lineLimit(1)
				.truncationMode(.middle)
		}
		.padding(.vertical, 2)
	}
}

// MARK: - Editor (detail)

private struct EditorView: View {
	@Bindable var viewModel: AppViewModel
	@State private var isMontageSheetPresented = false

	var body: some View {
		VStack(spacing: 0) {
			if viewModel.hasImages {
				HSplitView {
					PreviewPane(
						title: viewModel.originalTitle,
						image: viewModel.currentOriginalImage,
						emptyMessage: "No images selected yet"
					)
					PreviewPane(
						title: viewModel.processedTitle,
						image: viewModel.currentProcessedImage,
						emptyMessage: "No processed image yet"
					)
				}
				.frame(minWidth: 480)
			} else {
				WelcomeView { viewModel.selectImages() }
			}

			Divider()
			StatusBar(viewModel: viewModel)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.navigationTitle("Bordr")
		.toolbar { toolbarContent }
		.sheet(isPresented: $isMontageSheetPresented) {
			MontageSheet(viewModel: viewModel)
		}
		.dropDestination(for: URL.self) { urls, _ in
			viewModel.addImages(urls: urls)
			return true
		}
	}

	@ToolbarContentBuilder
	private var toolbarContent: some ToolbarContent {
		ToolbarItemGroup(placement: .primaryAction) {
			Button {
				viewModel.selectImages()
			} label: {
				Label("Select Images", systemImage: "photo.badge.plus")
			}
			.help("Choose images to process (⌘O)")
			.keyboardShortcut("o", modifiers: .command)

			Button {
				viewModel.processSelectedImages()
			} label: {
				Label("Process", systemImage: "wand.and.stars")
			}
			.help("Resize and place on the selected canvas (⌘↩)")
			.keyboardShortcut(.return, modifiers: .command)
			.disabled(!viewModel.hasImages || viewModel.isLoading)

			Button {
				isMontageSheetPresented = true
			} label: {
				Label("Contact Sheet", systemImage: "rectangle.grid.2x2")
			}
			.help("Combine the selected images into one contact sheet")
			.disabled(viewModel.originalImages.count < 2 || viewModel.isLoading)

			Button {
				viewModel.processSelectedImageForScroll()
			} label: {
				Label("Process for Scroll", systemImage: "rectangle.split.2x1")
			}
			.help("Split the current image into swipable halves")
			.disabled(!viewModel.hasImages || viewModel.isLoading)

			AspectRatioPicker(selection: $viewModel.currentAspectRatio)
				.disabled(!viewModel.hasImages || viewModel.isLoading)
		}
	}
}

private struct AspectRatioPicker: View {
	@Binding var selection: AspectRatio

	var body: some View {
		Picker("Aspect Ratio", selection: $selection) {
			ForEach(AspectRatio.allCases) { ratio in
				Text(ratio.id).tag(ratio)
			}
		}
		.pickerStyle(.segmented)
		.help("Output aspect ratio")
	}
}

// MARK: - Preview pane

private struct PreviewPane: View {
	let title: String
	let image: NSImage?
	let emptyMessage: String

	var body: some View {
		VStack(spacing: 10) {
			Text(title)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)

			ZStack {
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.fill(Color(nsColor: .controlBackgroundColor))

				if let image {
					Image(nsImage: image)
						.resizable()
						.interpolation(.high)
						.scaledToFit()
						.padding(12)
				} else {
					VStack(spacing: 8) {
						Image(systemName: "photo.on.rectangle.angled")
							.font(.system(size: 30))
							.foregroundStyle(.tertiary)
						Text(emptyMessage)
							.font(.callout)
							.foregroundStyle(.secondary)
					}
					.padding()
				}
			}
			.overlay(
				RoundedRectangle(cornerRadius: 12, style: .continuous)
					.strokeBorder(Color(nsColor: .separatorColor))
			)
		}
		.padding(16)
		.frame(minWidth: 220, maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
	}
}

// MARK: - Welcome / empty state

private struct WelcomeView: View {
	let onSelect: () -> Void

	var body: some View {
		VStack(spacing: 16) {
			Image(systemName: "photo.stack")
				.font(.system(size: 52))
				.foregroundStyle(.tertiary)

			Text("No images selected")
				.font(.title2.weight(.semibold))

			Text("Choose photos to resize, add borders, or build a contact sheet.")
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)

			Button(action: onSelect) {
				Label("Select Images", systemImage: "photo.badge.plus")
			}
			.controlSize(.large)
			.buttonStyle(.borderedProminent)
			.padding(.top, 4)

			Text("…or drag images anywhere in this window.")
				.font(.footnote)
				.foregroundStyle(.tertiary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}
}

// MARK: - Status bar

private struct StatusBar: View {
	@Bindable var viewModel: AppViewModel

	var body: some View {
		HStack(spacing: 12) {
			statusMessage
			Spacer()
			if viewModel.hasImages {
				navigationControls
			}
		}
		.padding(.horizontal, 16)
		.frame(height: 44)
		.background(.bar)
	}

	@ViewBuilder
	private var statusMessage: some View {
		if viewModel.isLoading {
			HStack(spacing: 8) {
				ProgressView().controlSize(.small)
				Text("Processing…").foregroundStyle(.secondary)
			}
		} else if let error = viewModel.errorMessage {
			HStack(spacing: 8) {
				Image(systemName: "exclamationmark.triangle.fill")
					.foregroundStyle(.yellow)
				Text(error)
					.lineLimit(1)
					.truncationMode(.middle)
					.foregroundStyle(.secondary)
			}
		} else if let url = viewModel.inputImageURLs[safe: viewModel.currentImageIndex] {
			Text(url.lastPathComponent)
				.lineLimit(1)
				.truncationMode(.middle)
				.foregroundStyle(.secondary)
		}
	}

	private var navigationControls: some View {
		HStack(spacing: 12) {
			Button {
				viewModel.selectPrevious()
			} label: {
				Image(systemName: "chevron.left")
			}
			.buttonStyle(.borderless)
			.help("Previous image (←)")

			Text("\(min(viewModel.currentImageIndex + 1, viewModel.imageCount)) / \(viewModel.imageCount)")
				.monospacedDigit()
				.foregroundStyle(.secondary)

			Button {
				viewModel.selectNext()
			} label: {
				Image(systemName: "chevron.right")
			}
			.buttonStyle(.borderless)
			.help("Next image (→)")
		}
	}
}

// MARK: - Contact sheet sheet

private struct MontageSheet: View {
	@Bindable var viewModel: AppViewModel
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			Text("Contact Sheet")
				.font(.title3.weight(.semibold))

			Text("Combine \(viewModel.originalImages.count) images into a single sheet.")
				.font(.callout)
				.foregroundStyle(.secondary)

			Form {
				ColorPicker("Background Color", selection: $viewModel.montage.bgColor, supportsOpacity: false)
				Toggle("Individual Image Borders", isOn: $viewModel.montage.isBordered)
			}
			.formStyle(.grouped)

			HStack {
				Spacer()
				Button("Cancel", role: .cancel) { dismiss() }
					.keyboardShortcut(.cancelAction)
				Button("Generate") {
					let montage = viewModel.montage
					dismiss()
					viewModel.processSelectedImagesAsCollage(montage: montage)
				}
				.keyboardShortcut(.defaultAction)
				.buttonStyle(.borderedProminent)
			}
		}
		.padding(20)
		.frame(width: 380)
	}
}

#Preview {
	ContentView()
}
