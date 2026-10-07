//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftfinPlaybackPreviews
import SwiftfinUIState
import SwiftUI

extension VideoPlayer.PlaybackControls {

    struct PreviewImageView: View {

        @EnvironmentObject
        private var scrubbedSecondsBox: PublishedBox<Duration>

        @StateObject
        private var selection: PreviewImageSelection

        init(previewImageProvider: any PreviewImageProvider) {
            _selection = StateObject(wrappedValue: PreviewImageSelection(provider: previewImageProvider))
        }

        private var scrubbedSeconds: Duration {
            scrubbedSecondsBox.value
        }

        var body: some View {
            ZStack {
                Color.black

                ZStack {
                    if let image = selection.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .id(selection.index)
            }
            .onAppear {
                selection.request(scrubbedSeconds)
            }
            .onDisappear {
                selection.stop()
            }
            .onChange(of: scrubbedSeconds) {
                selection.request(scrubbedSeconds)
            }
        }
    }
}
