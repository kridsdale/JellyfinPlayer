//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import SwiftfinText
import SwiftUI

extension String: Displayable {

    var displayTitle: String {
        self
    }
}

extension String: @retroactive Identifiable {

    public var id: String {
        self
    }
}

extension String: LibraryElement {

    func makeBody(
        libraryStyle: LibraryStyle,
        action: (() -> Void)?
    ) -> some View {
        StringLibraryListElement(
            value: self,
            action: action
        )
    }
}

private struct StringLibraryListElement: View {

    @Environment(\.isEditing)
    private var isEditing
    @Environment(\.isSelected)
    private var isSelected

    let value: String
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack {
                Text(value.displayTitle)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(
                        isEditing ? (isSelected ? .primary : .secondary) : .primary
                    )

                if isEditing {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }
            }
        }
        .foregroundStyle(.primary, .secondary)
    }
}

// Value text operations are owned by SwiftfinText; app display/list composition stays here.
