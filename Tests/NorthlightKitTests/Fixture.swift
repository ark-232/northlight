import Foundation
import Testing

/// A response saved from the live service, from the Fixtures folder.
func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func utc(_ string: String) -> Date {
    try! Date(string, strategy: .iso8601)
}
