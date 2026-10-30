import AppKit
import NorthlightAgent
import NorthlightKit
import Observation

/// Signs in to GitHub on this Mac, reads the account every 15 minutes and the inbox
/// and Actions runs every 5 while the Mac is awake, and pushes it to the TV with the
/// redaction list applied. Private repositories' headlines, titles and branches go
/// too, since the list, not GitHub's flag, decides what the room sees.
@MainActor
@Observable
final class GitHubConnector {
    enum Step: Equatable {
        case signedOut, starting
        case showing(GitHubDeviceFlow.Code)
        case signedIn
        case failed(String)
    }

    private(set) var step: Step
    /// What was last sent, or why nothing was.
    private(set) var status = ""

    private let feed: AgentFeed
    private let http = HTTP(userAgent: "Northlight/1.0")
    private var token: String?
    /// The account as GitHub gave it, before redaction, so a change to the list
    /// is pushed at once.
    private var fetched: Pushed<GitHubPush>?
    private var summaryFetchedAt: Date?
    private var linesFetchedAt: Date?
    private var signingIn: Task<Void, Never>?
    private var fetching: Task<Void, Never>?

    /// The latest push, for a TV that connects after it.
    var frame: Frame? { redacted.map { .github($0) } }

    init(feed: AgentFeed) {
        self.feed = feed
        let token = MacKeychain.read()
        self.token = token
        step = token == nil ? .signedOut : .signedIn
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.startFetching() }
        }
        startFetching()
        watchRedaction()
    }

    func signIn() {
        signingIn?.cancel()
        step = .starting
        signingIn = Task { [weak self, http] in
            do {
                let token = try await GitHubDeviceFlow.signIn(http: http) { @MainActor code in
                    self?.step = .showing(code)
                    self?.copyAndOpen(code)
                }
                guard let self else { return }
                let saved = MacKeychain.save(token)
                guard saved == errSecSuccess else {
                    step = .failed("The keychain refused the token (status \(saved)).")
                    return
                }
                self.token = token
                step = .signedIn
                startFetching()
            } catch is CancellationError {
            } catch {
                self?.step = .failed(DashboardStore.describe(error))
            }
        }
    }

    /// Puts the code on the clipboard and opens GitHub's page for it.
    func copyAndOpen(_ code: GitHubDeviceFlow.Code) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code.userCode, forType: .string)
        NSWorkspace.shared.open(code.verificationURI)
    }

    func cancelSignIn() {
        signingIn?.cancel()
        step = .signedOut
    }

    /// Forgets the token here and the account on the TV.
    func signOut() {
        fetching?.cancel()
        MacKeychain.delete()
        token = nil
        fetched = nil
        summaryFetchedAt = nil
        linesFetchedAt = nil
        step = .signedOut
        status = ""
        Task { await feed.push(.disconnected(.github)) }
    }

    private var redacted: Pushed<GitHubPush>? {
        fetched.map { fetched in
            var pushed = fetched
            pushed.value = fetched.value.map(AgentRedaction(blockedPathFragments: feed.blocked).redact)
            return pushed
        }
    }

    private func watchRedaction() {
        withObservationTracking { [feed] in
            _ = feed.blocked
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.push()
                self?.watchRedaction()
            }
        }
    }

    private func push() {
        guard let frame else { return }
        Task { await feed.push(frame) }
    }

    private func startFetching() {
        fetching?.cancel()
        guard let token else { return }
        let poll = GitHubNotificationPoll()
        fetching = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetch(token: token, poll: poll)
                try? await Task.sleep(for: .seconds(DashboardStore.Cadence.githubInbox))
            }
        }
    }

    /// The inbox and Actions runs every time, the summary every 15 minutes, then the
    /// lines of code once a day, which can take minutes while GitHub counts them, so
    /// the rest is pushed before they are asked for. An inbox or runs that fail keep
    /// their last reading.
    private func fetch(token: String, poll: GitHubNotificationPoll) async {
        let calendar = feed.place?.calendar ?? .current
        do {
            var summary = fetched?.value?.summary
            if summary == nil || summaryFetchedAt.map({ Date().timeIntervalSince($0) >= DashboardStore.Cadence.github }) ?? true {
                summary = try await http.github(token: token, calendar: calendar, keepsPrivateHeadlines: true)
                summaryFetchedAt = Date()
            }
            guard let summary, !Task.isCancelled else { return }
            async let inbox = try? http.githubInbox(token: token, poll: poll, keepsPrivateTitles: true)
            async let actions = try? http.githubActions(token: token, repositories: Array(summary.repositories.prefix(5)),
                                                        keepsPrivateBranches: true)
            let (newInbox, newActions) = await (inbox, actions)
            guard !Task.isCancelled else { return }
            record(GitHubPush(summary: summary, codeHistory: fetched?.value?.codeHistory,
                              inbox: newInbox ?? fetched?.value?.inbox, actions: newActions ?? fetched?.value?.actions))
            guard linesFetchedAt.map({ Date().timeIntervalSince($0) >= DashboardStore.Cadence.codeHistory }) ?? true,
                  let lines = try? await http.codeHistory(token: token, repositories: Array(summary.repositories.prefix(5))),
                  !Task.isCancelled
            else { return }
            linesFetchedAt = Date()
            record(GitHubPush(summary: summary, codeHistory: lines, inbox: fetched?.value?.inbox, actions: fetched?.value?.actions))
        } catch FeedError.badStatus(401) {
            signOut()
            step = .failed("GitHub no longer accepts this sign-in. Sign in again.")
        } catch where !Task.isCancelled {
            let reason = DashboardStore.describe(error)
            status = "GitHub: \(reason)"
            if var failed = fetched {
                failed.error = reason
                fetched = failed
                push()
            }
        } catch {}
    }

    private func record(_ value: GitHubPush) {
        fetched = Pushed(value: value, fetchedAt: Date(), interval: DashboardStore.Cadence.github, source: Mac.name)
        status = "Signed in as \(value.summary.login)"
        push()
    }
}
