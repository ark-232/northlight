import Foundation
import Testing
@testable import NorthlightKit

private func poll(_ json: String, interval: Int = 5) throws -> GitHubDeviceFlow.Poll {
    try GitHubDeviceFlow.poll(from: Data(json.utf8), interval: interval)
}

@Test func aPendingSignInWaitsTheInterval() throws {
    #expect(try poll(#"{"error":"authorization_pending","error_description":"pending"}"#) == .wait(seconds: 5))
}

@Test func slowDownAddsFiveSecondsOrTakesGitHubsInterval() throws {
    #expect(try poll(#"{"error":"slow_down"}"#, interval: 5) == .wait(seconds: 10))
    #expect(try poll(#"{"error":"slow_down","interval":15}"#, interval: 5) == .wait(seconds: 15))
}

@Test func anApprovedSignInYieldsTheToken() throws {
    #expect(try poll(#"{"access_token":"gho_abc","token_type":"bearer","scope":"repo,read:user"}"#) == .token("gho_abc"))
}

@Test func aDeniedOrExpiredCodeFailsWithAReason() throws {
    #expect(try poll(#"{"error":"access_denied"}"#) == .failed("Sign-in was cancelled on GitHub."))
    #expect(try poll(#"{"error":"expired_token"}"#) == .failed("The code expired. Start again."))
}

@Test func theDeviceCodeDecodes() throws {
    let json = Data(#"{"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#.utf8)
    let code = try GitHubDeviceFlow.code(from: json)
    #expect(code.userCode == "WDJB-MJHT")
    #expect(code.verificationURI.absoluteString == "https://github.com/login/device")
    #expect(code.interval == 5)
}

@Test func aRefusedCodeRequestReadsAsGitHubsReason() {
    let disabled = Data(#"{"error":"device_flow_disabled","error_description":"Device Flow must be explicitly enabled for this App"}"#.utf8)
    #expect(throws: FeedError.refused("Device Flow must be explicitly enabled for this App")) {
        try GitHubDeviceFlow.code(from: disabled)
    }
    // An unknown client ID answers 404 with an error and no description.
    #expect(throws: FeedError.refused("Not Found")) {
        try GitHubDeviceFlow.code(from: Data(#"{"error":"Not Found"}"#.utf8))
    }
}
