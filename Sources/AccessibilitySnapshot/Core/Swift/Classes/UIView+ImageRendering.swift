//
//  Copyright 2023 Block Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreImage
import UIKit

public enum ImageRenderingError: Swift.Error {

    /// An error indicating that the `containedView` is too large too snapshot using the specified rendering
    /// parameters.
    ///
    /// - Note: This error is thrown due to filters failing. To avoid this error, try rendering the snapshot in
    /// polychrome, reducing the size of the `containedView`, or running on a different iOS version. In particular,
    /// this error is known to occur when rendering a monochrome snapshot on iOS 13.
    case containedViewExceedsMaximumSize(viewSize: CGSize, maximumSize: CGSize)

    /// An error indicating that the `containedView` has a transform that is not support while using the specified
    /// rendering parameters.
    ///
    /// - Note: In particular, this error is known to occur when using a non-identity transform that requires
    /// tiling. To avoid this error, try setting an identity transform on the `containedView` or using the
    /// `.renderLayerInContext` view rendering mode
    case containedViewHasUnsupportedTransform(transform: CATransform3D)

    /// An error indicating the `containedView` has an invalid size due to the `width` and/or `height` being zero.
    case containedViewHasZeroSize(viewSize: CGSize)

}

extension UIView {

    func renderToImage(
        monochrome: Bool,
        viewRenderingMode: AccessibilitySnapshotView.ViewRenderingMode
    ) throws -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)

        var error: Error?

        let snapshot = renderer.image { context in
            switch viewRenderingMode {
            case .drawHierarchyInRect:
                drawHierarchy(in: bounds, afterScreenUpdates: true)

            case .renderLayerInContext:
                layer.render(in: context.cgContext)
            }
        }

        if let error = error {
            throw error
        }

        if monochrome {
            return try monochromeSnapshot(for: snapshot) ?? snapshot

        } else {
            return snapshot
        }
    }

    private func monochromeSnapshot(for snapshot: UIImage) throws -> UIImage? {
        if ProcessInfo().operatingSystemVersion.majorVersion == 13 {
            // On iOS 13, the image filter silently fails for large images, "successfully" producing a blank output
            // image. From testing, the maximum support size is 1365x1365 pt. Exceeding that in either dimension will
            // result in a blank image.
            let maximumSize = CGSize(width: 1365, height: 1365)
            if snapshot.size.width > maximumSize.width || snapshot.size.height > maximumSize.height {
                throw ImageRenderingError.containedViewExceedsMaximumSize(
                    viewSize: snapshot.size,
                    maximumSize: maximumSize
                )
            }
        }

        guard let inputImage = CIImage(image: snapshot) else {
            return nil
        }

        let monochromeFilter = CIFilter(
            name: "CIColorControls",
            parameters: [
                kCIInputImageKey: inputImage,
                kCIInputSaturationKey: 0,
            ]
        )!

        let context = CIContext()

        guard
            let outputImage = monochromeFilter.outputImage,
            let cgImage = context.createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static let tileSideLength: CGFloat = 2000

}
