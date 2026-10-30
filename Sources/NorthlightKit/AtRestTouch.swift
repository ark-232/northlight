import Foundation

public enum Move: Equatable, Sendable { case left, right, up, down }

/// Reads one remote's touches at rest from its absolute dpad (x and y in -1...1, y up),
/// and turns them into page moves: a circle on the ring turns a page every quarter turn,
/// clockwise forward, and a straight swipe turns one at lift. Pure: the caller passes
/// each report's time, and no clock is read.
///
/// Thresholds come from the owner's Siri Remote (2nd gen) recording, the test fixture.
public struct AtRestTouch: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Degrees turned past the last page line, clockwise positive.
        case ring(sinceDetent: Double)
        /// Pad units the finger has moved across since touchdown.
        case pan(dx: Double)
    }

    /// Circles stayed at or beyond 0.55 until claimed; swipes dipped to 0.12 or less.
    static let ringMinRadius = 0.45
    /// Swipes turn 6 degrees at most above radius 0.5.
    static let ringClaim = 30.0
    /// A claimed circle strayed in to 0.34 and kept turning.
    static let countMinRadius = 0.25
    /// A touch that began as a pan claims the ring after 45 degrees out here; a straight
    /// line through the middle turns 37.5 at most.
    static let rearmMinRadius = 0.5
    static let rearmClaim = 45.0
    static let step = 90.0
    /// Turning back this far past the last line undoes its page.
    static let undo = 30.0
    /// A resting thumb crept 58 degrees a second; a deliberate circle runs 270 and up.
    static let driftWindow = 0.25
    static let driftDegrees = 15.0
    /// A resting finger is silent, so a move this long after a report is a click.
    static let quiet = 0.1
    static let clickAfterSwipe = 0.01
    static let swipeChord = 0.5
    static let swipeStraightness = 0.6
    static let swipeAxisRatio = 1.5
    /// Release speed is measured over the last 50 ms before lift, in pad units a second.
    static let releaseWindow = 0.05

    /// Pages a sideways swipe turns for its release speed. The recorded swipes, asked
    /// for one page each, left the pad at 2.7 to 10.3 units a second.
    public static func pages(forSpeed speed: Double) -> Int {
        switch abs(speed) {
        case 22...: 3
        case 15...: 2
        default: 1
        }
    }

    private struct Point: Sendable {
        var x = 0.0, y = 0.0
        var time = 0.0
        var radius: Double { hypot(x, y) }
    }

    private enum State: Sendable { case idle, pending, ring, pan, cancelled }

    private var state = State.idle
    private var start = Point()
    private var last = Point()
    private var path = 0.0
    /// The newest report at least `releaseWindow` old, then every report since.
    private var recent: [Point] = []
    private var angle = 0.0
    private var detents = 0
    private var rearm = 0.0
    private var checkpoint = (time: 0.0, angle: 0.0)
    private var pressed = false
    private var lastReport: TimeInterval?
    private var lastSwipe: TimeInterval?

    public init() {}

    public var phase: Phase {
        switch state {
        case .ring: .ring(sinceDetent: angle - Double(detents) * Self.step)
        case .pan: .pan(dx: last.x - start.x)
        case .idle, .pending, .cancelled: .idle
        }
    }

    /// One dpad report; (0, 0) is a lift. GameController calls back once per changed
    /// axis, so a report with one axis at zero is half an update and is skipped.
    public mutating func feed(x: Double, y: Double, at time: TimeInterval) -> [Move] {
        if x == 0, y == 0 { return lift(at: time) }
        lastReport = time
        guard x != 0, y != 0 else { return [] }
        let point = Point(x: x, y: y, time: time)
        switch state {
        case .idle:
            begin(at: point, time: time)
            return []
        case .cancelled:
            return []
        case .pending, .ring, .pan:
            return move(to: point, at: time)
        }
    }

    /// The clickpad's press. Going down during a touch hands the touch to the click.
    public mutating func press(_ down: Bool) {
        if down, !pressed, state != .idle { state = .cancelled }
        pressed = down
    }

    /// Silences the touch under way until it lifts.
    public mutating func cancel() {
        if state != .idle { state = .cancelled }
    }

    /// Whether a move tvOS sends now came from a click rather than a finger on the pad.
    public func acceptsMove(at time: TimeInterval) -> Bool {
        lastReport.map { time - $0 >= Self.quiet } ?? true
    }

    /// Whether a ring click now is its own input, not the press that ended a swipe.
    public func acceptsClick(at time: TimeInterval) -> Bool {
        lastSwipe.map { time - $0 > Self.clickAfterSwipe } ?? true
    }

    private mutating func begin(at point: Point, time: TimeInterval) {
        state = point.radius < Self.ringMinRadius ? .pan : .pending
        start = point
        last = point
        path = 0
        recent = [point]
        angle = 0
        detents = 0
        rearm = 0
        checkpoint = (time, 0)
    }

    private mutating func move(to point: Point, at time: TimeInterval) -> [Move] {
        let previous = last
        last = point
        path += hypot(point.x - previous.x, point.y - previous.y)
        recent.append(point)
        while recent.count > 1, time - recent[1].time >= Self.releaseWindow { recent.removeFirst() }
        let turned = -remainder(atan2(point.y, point.x) - atan2(previous.y, previous.x), 2 * .pi) * 180 / .pi

        switch state {
        case .pending:
            if previous.radius >= Self.ringMinRadius, point.radius >= Self.ringMinRadius { angle += turned }
            if time - checkpoint.time >= Self.driftWindow {
                if abs(angle - checkpoint.angle) < Self.driftDegrees { angle = 0 }
                checkpoint = (time, angle)
            }
            if point.radius < Self.ringMinRadius {
                state = .pan
            } else if abs(angle) >= Self.ringClaim {
                state = .ring
            }
        case .pan:
            let outside = previous.radius >= Self.rearmMinRadius && point.radius >= Self.rearmMinRadius
            rearm = outside ? rearm + turned : 0
            if abs(rearm) >= Self.rearmClaim {
                state = .ring
                angle = rearm
                detents = 0
            }
        case .ring:
            if previous.radius >= Self.countMinRadius, point.radius >= Self.countMinRadius { angle += turned }
        case .idle, .cancelled:
            break
        }
        return state == .ring ? crossedLines() : []
    }

    /// Page lines sit every quarter turn from touchdown. Crossing one turns a page;
    /// going back 30 degrees past it turns the page back.
    private mutating func crossedLines() -> [Move] {
        var moves: [Move] = []
        while true {
            let ahead = detents < 0 ? Double(detents) * Self.step + Self.undo : Double(detents + 1) * Self.step
            let behind = detents > 0 ? Double(detents) * Self.step - Self.undo : Double(detents - 1) * Self.step
            if angle >= ahead {
                detents += 1
                moves.append(.right)
            } else if angle <= behind {
                detents -= 1
                moves.append(.left)
            } else {
                return moves
            }
        }
    }

    private mutating func lift(at time: TimeInterval) -> [Move] {
        defer { state = .idle }
        guard state == .pan, let swipe = swipe() else { return [] }
        lastSwipe = time
        guard swipe == .left || swipe == .right, let first = recent.first, last.time > first.time else { return [swipe] }
        let speed = (last.x - first.x) / (last.time - first.time)
        return Array(repeating: swipe, count: Self.pages(forSpeed: speed))
    }

    private func swipe() -> Move? {
        let dx = last.x - start.x, dy = last.y - start.y
        let chord = hypot(dx, dy)
        guard chord >= Self.swipeChord, chord >= Self.swipeStraightness * path else { return nil }
        if abs(dx) >= Self.swipeAxisRatio * abs(dy) { return dx > 0 ? .right : .left }
        if abs(dy) >= Self.swipeAxisRatio * abs(dx) { return dy > 0 ? .up : .down }
        return nil
    }
}
