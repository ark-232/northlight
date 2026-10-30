import Testing
@testable import NorthlightKit

private func chroma(_ c: SkyMood.RGB) -> Double { max(c.red, c.green, c.blue) - min(c.red, c.green, c.blue) }
private func luminance(_ c: SkyMood.RGB) -> Double { 0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue }

@Test func aClearNightIsADarkBlue() {
    let night = SkyMood(sunElevation: -30, cloudCover: 0, auroraProbability: 0)
    #expect(night.colors.count == 9)
    #expect(night.colors.allSatisfy { $0.blue > $0.red && luminance($0) < 0.1 })
    #expect(night.drift == 1)
}

@Test func theHorizonWarmsAroundSunset() {
    let golden = SkyMood(sunElevation: 3, cloudCover: 0, auroraProbability: nil)
    let night = SkyMood(sunElevation: -30, cloudCover: 0, auroraProbability: nil)
    // The middle of the bottom row is the horizon; the middle of the top row is overhead.
    #expect(golden.colors[7].red > golden.colors[1].red)
    #expect(golden.colors[7].red > night.colors[7].red + 0.1)
}

@Test func cloudDullsTheSky() {
    let clear = SkyMood(sunElevation: 3, cloudCover: 0, auroraProbability: nil)
    let overcast = SkyMood(sunElevation: 3, cloudCover: 100, auroraProbability: nil)
    for (sunlit, dull) in zip(clear.colors, overcast.colors) {
        #expect(chroma(dull) < chroma(sunlit))
    }
}

@Test func aLikelyAuroraGreensTheTopOfADarkSky() {
    let aurora = SkyMood(sunElevation: -20, cloudCover: 0, auroraProbability: 60)
    #expect(aurora.colors[0..<3].allSatisfy { $0.green > $0.blue })
    #expect(aurora.drift > 1)
    // Not in twilight, and not through cloud.
    #expect(SkyMood(sunElevation: -5, cloudCover: 0, auroraProbability: 60) == SkyMood(sunElevation: -5, cloudCover: 0, auroraProbability: 0))
    #expect(SkyMood(sunElevation: -20, cloudCover: 100, auroraProbability: 60) == SkyMood(sunElevation: -20, cloudCover: 100, auroraProbability: 0))
}

@Test func theSkyMovesWithTheSunWithoutSteps() {
    var previous = SkyMood(sunElevation: -40, cloudCover: 30, auroraProbability: 40)
    var largest = 0.0
    for tenth in -399...400 {
        let mood = SkyMood(sunElevation: Double(tenth) / 10, cloudCover: 30, auroraProbability: 40)
        for (a, b) in zip(previous.colors, mood.colors) {
            largest = max(largest, abs(a.red - b.red), abs(a.green - b.green), abs(a.blue - b.blue))
        }
        previous = mood
    }
    // A tenth of a degree of sun, about 30 seconds, never moves a channel by 1 %.
    #expect(largest < 0.01)
}

@Test func theSkyStaysDarkBehindTheTiles() {
    for elevation in stride(from: -90.0, through: 90, by: 1) {
        for cloud in [nil, 0, 50, 100] as [Int?] {
            for aurora in [nil, 0, 100] as [Int?] {
                let mood = SkyMood(sunElevation: elevation, cloudCover: cloud, auroraProbability: aurora)
                #expect(mood.colors.allSatisfy { luminance($0) < 0.3 }, "\(elevation)")
            }
        }
    }
}

/// True when the mesh's outer points all sit on the screen's edges.
private func coversTheScreen(_ p: [SIMD2<Float>]) -> Bool {
    let top = p[0..<3].allSatisfy { $0.y == 0 }
    let bottom = p[6..<9].allSatisfy { $0.y == 1 }
    let left = [p[0], p[3], p[6]].allSatisfy { $0.x == 0 }
    let right = [p[2], p[5], p[8]].allSatisfy { $0.x == 1 }
    return top && bottom && left && right
}

@Test func theMeshKeepsToTheScreensEdgesAsItDrifts() {
    let calm = SkyMood(sunElevation: -30, cloudCover: 0, auroraProbability: 0)
    let aurora = SkyMood(sunElevation: -30, cloudCover: 0, auroraProbability: 90)
    for mood in [calm, aurora] {
        let frames = stride(from: 0.0, through: 600, by: 7.3).map(mood.points(at:))
        #expect(frames.allSatisfy(coversTheScreen))
        // And it still moves.
        #expect(Set(frames).count == frames.count)
    }
}
