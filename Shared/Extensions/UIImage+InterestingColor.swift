//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinImageProcessing
import SwiftUI
import UIKit

extension UIImage {
    func interestingColor() -> Color? {
        guard let cgImage, let sample = ImagePalette.interestingColor(in: cgImage) else { return nil }
        return Color(uiColor: UIColor(red: sample.red, green: sample.green, blue: sample.blue, alpha: 1))
    }
}
