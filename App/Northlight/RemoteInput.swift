import Foundation
import GameController
import NorthlightKit

/// The Siri Remote's clickpad at rest, read through GameController: ring turns, swipes
/// and ring clicks become page moves, with nothing focused. Only remotes with a full
/// touch surface are read; the iPhone remote and the 1st-gen remote reach the app
/// through tvOS's moves alone.
@MainActor @Observable final class RemoteInput {
    /// What the finger is doing, while at rest; idle otherwise.
    private(set) var phase: AtRestTouch.Phase = .idle
    /// Whether the dashboard is at rest and on screen; anything else silences the touch.
    var atRest = false {
        didSet {
            guard atRest != oldValue else { return }
            touch.cancel()
            phase = .idle
        }
    }
    @ObservationIgnored var onMove: (Move) -> Void = { _ in }

    @ObservationIgnored private var touch = AtRestTouch()
    @ObservationIgnored private var bound: [GCController] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// The ring direction held down, and when the last ring click came up.
    @ObservationIgnored private var ringHeld: Move?
    @ObservationIgnored private var ringReleased: TimeInterval = -.infinity
    /// tvOS sends a ring click's move and Select on release, a few ms either side of
    /// GameController's release.
    private static let echo = 0.05

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebind() }
            })
        }
        rebind()
    }

    /// Whether a move tvOS sends now came from a click, not a finger on the pad or the
    /// ring click already taken.
    func acceptsMove() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return !echoesRingClick(at: now) && touch.acceptsMove(at: now)
    }

    /// Whether Select now is its own click rather than a ring click's.
    func acceptsSelect() -> Bool {
        !echoesRingClick(at: ProcessInfo.processInfo.systemUptime)
    }

    private func echoesRingClick(at time: TimeInterval) -> Bool {
        ringHeld != nil || time - ringReleased < Self.echo
    }

    private func rebind() {
        let live = GCController.controllers()
        bound.removeAll { controller in !live.contains { $0 === controller } }
        for controller in live where !bound.contains(where: { $0 === controller }) {
            bind(controller)
        }
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.microGamepad as? GCDirectionalGamepad,
              controller.productCategory != GCProductCategoryControlCenterRemote,
              controller.productCategory != GCProductCategorySiriRemote1stGen else { return }
        bound.append(controller)
        controller.handlerQueue = .main
        pad.reportsAbsoluteDpadValues = true
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.feed(x: Double(x), y: Double(y)) }
        }
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated { self?.touch.press(pressed) }
        }
        // The outer ring's physical click, on the way down; tvOS's own move for it
        // comes only on release.
        if let ring = controller.physicalInputProfile.dpads[GCInputDirectionalCardinalDpad] {
            for (button, move) in [(ring.left, Move.left), (ring.right, Move.right)] {
                button.pressedChangedHandler = { [weak self] _, _, pressed in
                    MainActor.assumeIsolated { self?.ring(move, pressed: pressed) }
                }
            }
        }
    }

    private func feed(x: Double, y: Double) {
        let moves = touch.feed(x: x, y: y, at: ProcessInfo.processInfo.systemUptime)
        guard atRest else { return }
        moves.forEach(onMove)
        if touch.phase != phase { phase = touch.phase }
    }

    private func ring(_ move: Move, pressed: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard pressed else {
            if ringHeld == move {
                ringHeld = nil
                ringReleased = now
            }
            return
        }
        ringHeld = move
        if atRest, touch.acceptsClick(at: now) { onMove(move) }
    }
}
