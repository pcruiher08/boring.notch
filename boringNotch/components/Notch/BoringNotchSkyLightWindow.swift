//
//  BoringNotchSkyLightWindow.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class BoringNotchSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        updateCollectionBehavior()
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
            
        Defaults.publisher(.hideNonNotchedFromMissionControl)
            .sink { [weak self] _ in
                self?.updateCollectionBehavior()
            }
            .store(in: &observers)
            
        NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification, object: self)
            .sink { [weak self] _ in
                self?.updateCollectionBehavior()
            }
            .store(in: &observers)
        
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: self)
            .sink { [weak self] _ in
                self?.cleanupObservers()
            }
            .store(in: &observers)
    }
    
    private func updateCollectionBehavior() {
        var newBehavior: NSWindow.CollectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        let hasNotch = (self.screen?.safeAreaInsets.top ?? 0) > 0
        
        if Defaults[.hideNonNotchedFromMissionControl] && !hasNotch {
            newBehavior.insert(.transient)
        }
        
        collectionBehavior = newBehavior
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    private func cleanupObservers() {
        Task { @MainActor in
            self.observers.forEach { $0.cancel() }
            self.observers.removeAll()
        }
    }
    
    // MARK: - Conditional key focus

    /// Set only while something in the notch genuinely needs keyboard input — currently, the
    /// shelf having a selection so Delete can remove it. Taking key status does activate the
    /// app, so the frontmost application loses focus for as long as this is set; releasing it
    /// deactivates us again and focus returns. That is why it is scoped as tightly as
    /// possible and dropped the moment the selection goes away.
    var allowsKeyFocus: Bool = false {
        didSet {
            guard allowsKeyFocus != oldValue else { return }
            if allowsKeyFocus {
                makeKey()
            } else if isKeyWindow {
                releaseKeyFocus()
            }
        }
    }

    /// AppKit has no API for handing key status back to whoever held it before. `resignKey()`
    /// looks like the candidate but is only a notification hook — it *tells* a window it has
    /// lost key status rather than transferring it, so calling it leaves this panel holding
    /// the keyboard indefinitely.
    ///
    /// Ordering the window out does drop key status (and deactivates the app); ordering it
    /// straight back in restores the notch within the same runloop turn.
    private func releaseKeyFocus() {
        orderOut(nil)
        orderFrontRegardless()
    }

    /// Called for key events reaching the window. Return `true` to consume the event so it
    /// does not fall through to the frontmost application.
    var onKeyDown: ((NSEvent) -> Bool)?

    /// Takes key focus only while the notch is open *and* the shelf has a selection, and
    /// routes Delete to the shelf while it does.
    func observeShelfKeyboardFocus(of viewModel: BoringViewModel) {
        Publishers.CombineLatest(
            ShelfSelectionModel.shared.$selectedIDs,
            viewModel.$notchState
        )
        .map { selectedIDs, notchState in
            !selectedIDs.isEmpty && notchState == .open
        }
        .removeDuplicates()
        .sink { [weak self] needsKeyboard in
            self?.allowsKeyFocus = needsKeyboard
        }
        .store(in: &observers)

        onKeyDown = { event in
            ShelfActionService.handleKeyDown(event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override var canBecomeKey: Bool { allowsKeyFocus }
    override var canBecomeMain: Bool { false }
}
