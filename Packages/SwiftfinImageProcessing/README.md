# SwiftfinImageProcessing

Owns bounded CoreGraphics sampling, inherited median-cut color-interest policy, alpha/PNG/JPEG selection and byte-limit validation. It has no account, catalog, network, settings or localization dependency. Immutable normalized color and encoded-byte values are checked Sendable; processing can run independently of the UI actor.

Sampling preserves the 48-pixel maximum dimension, low interpolation, premultiplied RGBA bytes, alpha >127 filter, five-bit histogram, six-color median cut and original interest ranking. Context draw/read work stays inside the pixel buffer's explicit lifetime. UIKit encoding remains a main-actor adapter inside this owner and delegates to the same pngData()/jpegData(compressionQuality:1) SDK calls. The app retains Color/UIColor construction and the existing localized upload-error message.

A fixture was captured by independently executing both complete original sources at c5b3e16b against synthetic CoreGraphics images and byte producers. Native contracts verify nine frozen pixel cases, 28 encoding cases, selected output/byte preservation, producer ordering, fallback/limit/failure rules, alpha flags and independent-executor processing. UIKit binary contracts compile in the validation host but remain unexecuted during the human's simulator-testing hold. No household media, image assets, network URLs or server state are opened.
