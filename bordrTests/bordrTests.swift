//
//  bordrTests.swift
//  bordrTests
//
//  Created by v on 7/21/25.
//

import Testing
@testable import bordr

struct bordrTests {

    /// Regression: clamping `currentImageIndex` in a `didSet` self-assigned
    /// through the @Observable setter and recursed until the stack overflowed.
    @MainActor
    @Test func clearingImagesDoesNotRecurse() {
        let viewModel = AppViewModel()
        viewModel.clearImages()
        #expect(viewModel.currentImageIndex == 0)
        #expect(viewModel.originalImages.isEmpty)
        #expect(viewModel.processedImages.isEmpty)
        #expect(viewModel.inputImageURLs.isEmpty)
    }
}
