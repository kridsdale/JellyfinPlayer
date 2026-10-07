//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if canImport(UIKit)
import SVGKit
import UIKit

/// SVGKit parsing and fast drawing remain private to the image owner. App UI
/// supplies bytes/layout; replacement and retirement follow the native view.
@MainActor
public final class NativeSVGRenderView: UIView {
    private let state = SVGRenderState<SVGKFastImageView>()

    public init(data: Data) {
        super.init(frame: .zero)
        backgroundColor = .clear
        update(data)
        frame.size = intrinsicContentSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(data:)")
    }

    override public var intrinsicContentSize: CGSize {
        state.rendered?.intrinsicContentSize ?? .zero
    }

    public func update(_ data: Data) {
        guard state.update(data, make: Self.makeRenderer) else { return }
        for view in subviews {
            view.removeFromSuperview()
        }
        if let rendered = state.rendered {
            rendered.frame = bounds
            rendered.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(rendered)
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    public func clear() {
        state.reset()
        for view in subviews {
            view.removeFromSuperview()
        }
        invalidateIntrinsicContentSize()
    }

    private static func makeRenderer(_ data: Data) -> SVGKFastImageView? {
        guard let image = SVGKImage(data: data), image.hasSize() else { return nil }
        let size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              let view = SVGKFastImageView(svgkImage: image) else { return nil }
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }
}
#endif
