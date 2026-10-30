import Foundation
import Testing
@testable import NorthlightKit

/// One touch of the recording: the moves while the finger was down, and the moves at lift.
private struct RecordedTouch {
    var during: [Move] = []
    var atLift: [Move] = []
    var net: Int { during.filter { $0 == .right }.count - during.filter { $0 == .left }.count }
}

/// The owner's Siri Remote (2nd gen) at rest, replayed callback by callback in log order:
/// 25 touches, and the time and verdict of each move tvOS sent.
private func replayRecording() throws -> (touches: [RecordedTouch], accepted: [Int], dropped: [Int]) {
    let url = try #require(Bundle.module.url(forResource: "siri-remote-2nd-gen", withExtension: "log", subdirectory: "Fixtures"))
    var reader = AtRestTouch()
    var touches = [RecordedTouch()]
    var accepted: [Int] = [], dropped: [Int] = []
    for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
        let field = line.split(separator: " ")
        guard field.count >= 3, let time = Double(field[0]) else { continue }
        let millis = Int((time.truncatingRemainder(dividingBy: 1000) * 1000).rounded())
        switch field[1] {
        case "dpad":
            let x = Double(field[2])!, y = Double(field[3])!
            let moves = reader.feed(x: x, y: y, at: time)
            if x == 0, y == 0 {
                touches[touches.count - 1].atLift += moves
                touches.append(RecordedTouch())
            } else {
                touches[touches.count - 1].during += moves
            }
        case "buttonA":
            reader.press(field[2] == "true")
        case "move":
            if reader.acceptsMove(at: time) { accepted.append(millis) } else { dropped.append(millis) }
        default:
            break
        }
    }
    return (touches, accepted, dropped)
}

struct AtRestTouchReplayTests {
    /// Net pages for each circle; the stuck-press window, 12 to 15, waits on a re-probe.
    let rings = [0: 2, 1: 7, 2: 2, 3: -1, 4: -10, 17: -4, 22: -4, 23: -3, 24: -2]
    let swipes: [Int: Move] = [5: .right, 6: .right, 7: .right, 8: .left, 9: .left, 10: .left]

    @Test func eachTouchTurnsTheRecordedPages() throws {
        let touches = try replayRecording().touches
        #expect(touches.count == 25)
        for (index, touch) in touches.enumerated() where !(12...15).contains(index) {
            if let net = rings[index] {
                #expect(touch.net == net, "touch \(index)")
                #expect(touch.atLift.isEmpty, "touch \(index)")
            } else if let swipe = swipes[index] {
                #expect(touch.during.isEmpty, "touch \(index)")
                #expect(touch.atLift == [swipe], "touch \(index)")
            } else {
                #expect(touch.during.isEmpty && touch.atLift.isEmpty, "touch \(index)")
            }
        }
    }

    @Test func noCircleTurnsAgainstItself() throws {
        let touches = try replayRecording().touches
        for (index, net) in rings {
            let against: Move = net > 0 ? .left : .right
            #expect(!touches[index].during.contains(against), "touch \(index)")
        }
    }

    /// Moves tvOS reads from a finger still on the pad go; the two ring clicks and the
    /// stuck-press window's moves, long after any report, stay.
    @Test func onlyMovesAfterAQuietPadAreAccepted() throws {
        let replay = try replayRecording()
        #expect(replay.accepted == [175_709, 179_430, 180_397, 181_281, 182_299, 183_600])
        #expect(replay.dropped.count == 13)
    }
}

/// A synthetic finger: arcs at 15 degrees a report, lines at 0.05 pad units, 15 ms apart.
private struct Finger {
    var reader = AtRestTouch()
    var time = 100.0
    var heading = 0.0
    var radius = 0.0
    var moves: [Move] = []

    mutating func report(_ x: Double, _ y: Double, after interval: Double = 0.015) {
        time += interval
        moves += reader.feed(x: x, y: y, at: time)
    }

    mutating func touch(r: Double, at degrees: Double) {
        radius = r
        heading = degrees
        place()
    }

    /// Clockwise is positive, so the heading, counted the math way, falls.
    mutating func arc(_ degrees: Double, step: Double = 15, interval: Double = 0.015) {
        let count = Int((abs(degrees) / step).rounded(.up))
        for _ in 0..<count {
            heading -= degrees / Double(count)
            place(after: interval)
        }
    }

    mutating func reach(r: Double) {
        radius = r
        place()
    }

    mutating func line(from start: (Double, Double), to end: (Double, Double), step: Double = 0.05) {
        let count = Int((hypot(end.0 - start.0, end.1 - start.1) / step).rounded(.up))
        for index in 0...count {
            let f = Double(index) / Double(count)
            report(start.0 + (end.0 - start.0) * f, start.1 + (end.1 - start.1) * f)
        }
    }

    mutating func lift() -> [Move] {
        let before = moves.count
        report(0, 0)
        return Array(moves[before...])
    }

    private mutating func place(after interval: Double = 0.015) {
        report(radius * cos(heading * .pi / 180), radius * sin(heading * .pi / 180), after: interval)
    }
}

struct AtRestTouchSyntheticTests {
    @Test func crossingTheSeamCountsTheSame() {
        var across = Finger(), clear = Finger()
        across.touch(r: 0.8, at: 240)
        across.arc(120)
        clear.touch(r: 0.8, at: 150)
        clear.arc(120)
        #expect(across.moves == [.right] && clear.moves == [.right])
        guard case .ring(let a) = across.reader.phase, case .ring(let b) = clear.reader.phase else {
            Issue.record("not a ring")
            return
        }
        #expect(abs(a - 30) < 0.001 && abs(b - 30) < 0.001)
    }

    @Test func aPageEveryQuarterTurn() {
        var finger = Finger()
        finger.touch(r: 0.8, at: 100)
        finger.arc(225)
        #expect(finger.moves == [.right, .right])
        finger.arc(45)
        #expect(finger.moves == [.right, .right, .right])
    }

    @Test func turningBackThirtyDegreesPastALineUndoesItsPage() {
        var finger = Finger()
        finger.touch(r: 0.8, at: 100)
        finger.arc(100)
        #expect(finger.moves == [.right])
        finger.arc(-25)
        #expect(finger.moves == [.right])
        finger.arc(-20)
        #expect(finger.moves == [.right, .left])
    }

    @Test func counterclockwiseTurnsBack() {
        var finger = Finger()
        finger.touch(r: 0.8, at: 10)
        finger.arc(-190)
        #expect(finger.moves == [.left, .left])
    }

    @Test func aCircleInsideTheRingDoesNothing() {
        var finger = Finger()
        finger.touch(r: 0.4, at: 100)
        finger.arc(360)
        #expect(finger.moves.isEmpty)
        #expect(finger.lift().isEmpty)
    }

    @Test func aClaimedRingKeepsCountingInsideButNotAtTheMiddle() {
        var inside = Finger(), middle = Finger()
        inside.touch(r: 0.8, at: 100)
        inside.arc(45)
        inside.reach(r: 0.3)
        inside.arc(60)
        middle.touch(r: 0.8, at: 100)
        middle.arc(45)
        middle.reach(r: 0.2)
        middle.arc(60)
        #expect(inside.moves == [.right])
        #expect(middle.moves.isEmpty)
    }

    @Test func aSwipeTurnsAtLiftAndNotBefore() {
        var finger = Finger()
        finger.line(from: (-0.8, 0.02), to: (0.8, 0.02))
        #expect(finger.moves.isEmpty)
        #expect(finger.lift() == [.right])

        var up = Finger()
        up.line(from: (0.02, -0.8), to: (0.02, 0.8))
        #expect(up.lift() == [.up])
    }

    @Test func aShortOrDiagonalSwipeDoesNothing() {
        var short = Finger()
        short.line(from: (-0.2, 0.02), to: (0.2, 0.02))
        #expect(short.lift().isEmpty)
        var diagonal = Finger()
        diagonal.line(from: (-0.5, -0.48), to: (0.5, 0.52))
        #expect(diagonal.lift().isEmpty)
        #expect(diagonal.moves.isEmpty)
    }

    @Test func aPressMidCircleStopsItAndTheNextTouchWorks() {
        var finger = Finger()
        finger.touch(r: 0.8, at: 100)
        finger.arc(60)
        finger.reader.press(true)
        finger.arc(120)
        finger.reader.press(false)
        #expect(finger.lift().isEmpty)
        #expect(finger.moves.isEmpty)
        finger.touch(r: 0.8, at: 100)
        finger.arc(100)
        #expect(finger.moves == [.right])
    }

    @Test func onlyAPressDuringATouchCancelsIt() {
        var finger = Finger()
        finger.reader.press(true)
        finger.touch(r: 0.8, at: 100)
        finger.arc(100)
        #expect(finger.moves == [.right])
    }

    @Test func halfUpdatesAtTouchdownAndLiftAddNoAngle() {
        var finger = Finger()
        let start = (x: 0.8 * cos(-30 * Double.pi / 180), y: 0.8 * sin(-30 * Double.pi / 180))
        finger.report(start.x, 0)
        finger.touch(r: 0.8, at: -30)
        finger.arc(-75)
        guard case .ring(let since) = finger.reader.phase else {
            Issue.record("not a ring")
            return
        }
        #expect(abs(since + 75) < 0.001)
        finger.report(0, 0.8 * sin(45 * Double.pi / 180))
        #expect(finger.lift().isEmpty)
        #expect(finger.moves.isEmpty)
    }

    @Test func cancelStaysSilentUntilLift() {
        var finger = Finger()
        finger.touch(r: 0.8, at: 100)
        finger.arc(60)
        finger.reader.cancel()
        finger.arc(120)
        #expect(finger.reader.phase == .idle)
        #expect(finger.lift().isEmpty)
        #expect(finger.moves.isEmpty)
        finger.touch(r: 0.8, at: 100)
        finger.arc(100)
        #expect(finger.moves == [.right])
    }

    /// Known limit: a straight swipe that stays on the ring reads as a quarter turn.
    @Test func aSwipeAlongTheRingReadsAsATurn() {
        var top = Finger(), bottom = Finger()
        top.line(from: (-0.8, 0.55), to: (0.8, 0.55))
        bottom.line(from: (-0.8, -0.55), to: (0.8, -0.55))
        #expect(top.moves == [.right])
        #expect(bottom.moves == [.left])
    }

    @Test func aCircleThatLandsInsideTheRingStillTurns() {
        var finger = Finger()
        finger.touch(r: 0.3, at: 100)
        #expect(finger.reader.phase == .pan(dx: 0))
        finger.reach(r: 0.8)
        finger.arc(200)
        #expect(finger.moves == [.right, .right])
        #expect(finger.lift().isEmpty)
    }

    @Test func aStraightSwipeThroughTheMiddleNeverClaimsTheRing() {
        var finger = Finger()
        finger.line(from: (-0.9, 0.32), to: (0.9, -0.28))
        #expect(finger.moves.isEmpty)
        #expect(finger.lift() == [.right])
    }

    @Test func aThumbRestingOnTheRingDoesNotDriftIntoATurn() {
        var finger = Finger()
        finger.touch(r: 0.72, at: 180)
        finger.arc(36, step: 0.8, interval: 0.015)
        #expect(finger.reader.phase == .idle)
        finger.arc(100)
        #expect(finger.moves == [.right])
    }

    @Test func aPanFollowsTheFingerAcross() {
        var finger = Finger()
        finger.line(from: (-0.2, 0.02), to: (0.1, 0.02))
        guard case .pan(let dx) = finger.reader.phase else {
            Issue.record("not a pan")
            return
        }
        #expect(abs(dx - 0.3) < 0.001)
    }

    @Test func movesWaitForAQuietPad() {
        var finger = Finger()
        #expect(finger.reader.acceptsMove(at: finger.time))
        finger.touch(r: 0.8, at: 100)
        let touched = finger.time
        #expect(!finger.reader.acceptsMove(at: touched + 0.05))
        #expect(finger.reader.acceptsMove(at: touched + 0.11))
        finger.report(0, 0.5, after: 0.02)
        #expect(!finger.reader.acceptsMove(at: touched + 0.11))
        finger.report(0, 0, after: 0.01)
        #expect(finger.reader.acceptsMove(at: touched + 0.13))
    }

    /// A press that lands just after a swipe's lift is the same gesture, not a second page.
    @Test func aClickRightAfterASwipeIsTheSwipe() {
        var finger = Finger()
        #expect(finger.reader.acceptsClick(at: finger.time))
        finger.line(from: (-0.8, 0.02), to: (0.8, 0.02))
        #expect(finger.lift() == [.right])
        #expect(!finger.reader.acceptsClick(at: finger.time + 0.005))
        #expect(finger.reader.acceptsClick(at: finger.time + 0.02))
    }
}

/// The recorded swipes left the pad at 2.7 to 10.3 units a second, so one page each
/// holds below 15, and flicks past it go further.
struct FlickTests {
    @Test func releaseSpeedScalesThePages() {
        #expect(AtRestTouch.pages(forSpeed: 10.3) == 1)
        #expect(AtRestTouch.pages(forSpeed: 14.9) == 1)
        #expect(AtRestTouch.pages(forSpeed: 15) == 2)
        #expect(AtRestTouch.pages(forSpeed: 21.9) == 2)
        #expect(AtRestTouch.pages(forSpeed: 22) == 3)
        #expect(AtRestTouch.pages(forSpeed: 60) == 3)
    }

    @Test func aFastFlickTurnsMoreThanOnePage() {
        var fast = Finger(), faster = Finger(), back = Finger()
        fast.line(from: (-0.9, 0.02), to: (0.9, 0.02), step: 0.3)
        faster.line(from: (-0.9, 0.02), to: (0.9, 0.02), step: 0.4)
        back.line(from: (0.9, 0.02), to: (-0.9, 0.02), step: 0.3)
        #expect(fast.lift() == [.right, .right])
        #expect(faster.lift() == [.right, .right, .right])
        #expect(back.lift() == [.left, .left])
    }

    @Test func aFastVerticalFlickStillEntersOnce() {
        var finger = Finger()
        finger.line(from: (0.02, -0.9), to: (0.02, 0.9), step: 0.4)
        #expect(finger.lift() == [.up])
    }
}
