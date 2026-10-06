//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

// TODO: Button recognizers for tvOS?
//       - .menu, .select

public class UIPreferencesHostingController: UIHostingController<AnyView> {

    public init(@ViewBuilder content: @escaping () -> some View) {

        _ = UIViewController.swizzle

        let box = Box()
        let rootView = AnyView(
            content()
                #if os(iOS)
                    .onPreferenceChange(KeyCommandsPreferenceKey.self) { value in
                        DispatchQueue.main.async { box.value?._keyCommandActions = value }
                    }
                    .onPreferenceChange(PrefersHomeIndicatorAutoHiddenPreferenceKey.self) { value in
                        DispatchQueue.main.async { box.value?._prefersHomeIndicatorAutoHidden = value }
                    }
                    .onPreferenceChange(PreferredScreenEdgesDeferringSystemGesturesPreferenceKey.self) { value in
                        DispatchQueue.main.async { box.value?._preferredScreenEdgesDeferringSystemGestures = value }
                    }
                    .onPreferenceChange(SupportedOrientationsPreferenceKey.self) { value in
                        DispatchQueue.main.async { box.value?._orientations = value }
                    }
                #elseif os(tvOS)
                    .onPreferenceChange(PressCommandsPreferenceKey.self) { value in
                        DispatchQueue.main.async { box.value?._pressCommandActions = value }
                    }
                #endif
        )

        super.init(rootView: rootView)

        box.value = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if os(iOS)

    // MARK: Key Commands

    private var _keyCommandActions: [KeyCommandAction] = [] {
        willSet {
            _keyCommands = newValue.map { action in
                let keyCommand = UIKeyCommand(
                    title: action.title,
                    action: #selector(keyCommandHit),
                    input: String(action.input),
                    modifierFlags: action.modifierFlags
                )

                keyCommand.subtitle = action.subtitle
                keyCommand.wantsPriorityOverSystemBehavior = true

                return keyCommand
            }
        }
    }

    private var _keyCommands: [UIKeyCommand] = []

    override public var keyCommands: [UIKeyCommand]? {
        _keyCommands
    }

    @objc
    private func keyCommandHit(keyCommand: UIKeyCommand) {
        guard let action = _keyCommandActions
            .first(where: { $0.input == keyCommand.input && $0.modifierFlags == keyCommand.modifierFlags }) else { return }
        action.action()
    }

    // MARK: Orientation

    var _orientations: UIInterfaceOrientationMask = .all {
        didSet {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        _orientations
    }

    override public var shouldAutorotate: Bool {
        true
    }

    // MARK: Defer Edges

    private var _preferredScreenEdgesDeferringSystemGestures: UIRectEdge = [.left, .right] {
        didSet { setNeedsUpdateOfScreenEdgesDeferringSystemGestures() }
    }

    override public var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        _preferredScreenEdgesDeferringSystemGestures
    }

    // MARK: Home Indicator Auto Hidden

    private var _prefersHomeIndicatorAutoHidden = false {
        didSet { setNeedsUpdateOfHomeIndicatorAutoHidden() }
    }

    override public var prefersHomeIndicatorAutoHidden: Bool {
        _prefersHomeIndicatorAutoHidden
    }
    #endif

    #if os(tvOS)

    override public func viewDidLoad() {
        super.viewDidLoad()

        let gesture = UITapGestureRecognizer(target: self, action: #selector(ignorePress))
        gesture.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(gesture)
    }

    @objc
    func ignorePress() {}

    private var _pressCommandActions: [PressCommandAction] = []

    var configuredPressCommands: [PressCommandAction] {
        _pressCommandActions
    }

    @discardableResult
    func performPressCommand(_ press: UIPress.PressType) -> Bool {
        guard let action = _pressCommandActions.first(where: { $0.press == press }) else { return false }
        action.action()
        return true
    }

    override public func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let buttonPress = presses.first?.type else { return }

        performPressCommand(buttonPress)
    }
    #endif
}
