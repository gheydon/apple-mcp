import Foundation

enum MessagesSender {
    static func send(to recipient: String, body: String, service: String = "iMessage") throws {
        let escapedRecipient = AppleScriptRunner.escape(recipient)
        let escapedBody = AppleScriptRunner.escape(body)
        let escapedService = AppleScriptRunner.escape(service)

        let script = """
            tell application "Messages"
                set targetService to 1st account whose service type = \(escapedService)
                set targetBuddy to participant "\(escapedRecipient)" of targetService
                send "\(escapedBody)" to targetBuddy
            end tell
            """
        _ = try AppleScriptRunner.run(script)
    }
}
