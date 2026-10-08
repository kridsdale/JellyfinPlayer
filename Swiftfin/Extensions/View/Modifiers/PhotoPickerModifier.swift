//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Mantis
import PhotosUI
import SwiftfinAsyncStreams
import SwiftUI

struct PhotoPickerModifier: ViewModifier {

    @Binding
    var isPresented: Bool

    @State
    private var selectedImage: UIImage?
    @State
    private var selectedItem: PhotosPickerItem?

    @State
    private var imageReads = AsyncOperationGate()

    let isSaving: Bool
    let cropShape: Mantis.CropShapeType
    let presetRatio: Mantis.PresetFixedRatioType
    let onSave: (UIImage) -> Void

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $selectedItem,
                matching: .images
            )
            .onChange(of: selectedItem) {
                loadImage(from: selectedItem)
            }
            .onDisappear { imageReads.cancel() }
            .sheet(isPresented: Binding<Bool>(
                get: { selectedImage != nil },
                set: {
                    if !$0 {
                        imageReads.cancel()
                        selectedImage = nil
                        selectedItem = nil
                    }
                }
            )) {
                if let image = selectedImage {
                    NavigationView {
                        PhotoCropView(
                            isSaving: isSaving,
                            image: image,
                            cropShape: cropShape,
                            presetRatio: presetRatio,
                            onSave: {
                                clearSelection()
                                onSave($0)
                            },
                            onCancel: clearSelection
                        )
                    }
                }
            }
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem?) {
        imageReads.cancel()
        guard let item else {
            selectedImage = nil
            return
        }

        let validate = imageReads.begin()
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               (try? validate()) != nil
            {
                selectedImage = image
            }
        }
    }

    private func clearSelection() {
        imageReads.cancel()
        selectedImage = nil
        selectedItem = nil
        isPresented = false
    }
}
