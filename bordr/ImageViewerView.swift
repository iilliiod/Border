//
//  ImageViewerView.swift
//  bordr
//
//  Created by v on 8/8/25.
//

import SwiftUI

struct ImageViewerView: View {
	@State var image: NSImage
	var body: some View {
		Image(nsImage: image)
			.resizable()
			.aspectRatio(contentMode: .fit)
			.frame(maxWidth: 400, maxHeight: 400)
	}
}
