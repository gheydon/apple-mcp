# apple-mcp

A native-Swift [Model Context Protocol](https://modelcontextprotocol.io) server
that exposes macOS **Calendar** and **Messages** to AI agents (Claude Code,
Claude Desktop, etc.). No Node, no Python, no shell glue — one statically-linked
Swift binary.

## Tools

| Tool | Description |
| --- | --- |
| `calendar_list_calendars` | List all calendars on the system |
| `calendar_list_events` | List events in a date range |
| `calendar_create_event` | Create a new event |
| `messages_list_chats` | List recent iMessage/SMS chats |
| `messages_recent` | Recent messages, optionally per chat |
| `messages_search` | Substring search over the `text` column |
| `messages_send` | Send a message via Messages.app |

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6.0+ / Xcode 16+

## Build

```sh
swift build -c release
```

The binary lands at `.build/release/apple-mcp`.

## Wire into Claude Code / Claude Desktop

Add to `~/.claude.json` (Claude Code) or `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple": {
      "command": "/absolute/path/to/apple-mcp/.build/release/apple-mcp"
    }
  }
}
```

## Permissions

macOS will prompt for these the first time each tool is used:

1. **Calendar** — *System Settings → Privacy & Security → Calendar*
   (granted on first `calendar_*` call; modern EventKit uses
   `requestFullAccessToEvents`)
2. **Full Disk Access** — must be granted *manually* to the parent process
   (Terminal, iTerm, Claude Code app) to let it read `~/Library/Messages/chat.db`
3. **Automation → Messages** — granted on first `messages_send`

## How it works

| Concern | Implementation |
| --- | --- |
| Calendar | `EventKit` framework, `EKEventStore` |
| Messages reading | Direct `SQLite3` access to `~/Library/Messages/chat.db` |
| `attributedBody` decoding | Hand-written typedstream scanner — modern Messages stores body text in an `NSArchiver`-format BLOB, not in the `text` column |
| Messages sending | `NSAppleScript` driving Messages.app (Apple provides no public Swift API for sending iMessages) |
| MCP protocol | Official [`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk) |

## Known limitations

- `messages_search` only matches the `text` column. Messages whose body lives
  solely in `attributedBody` are not matched. Decoding every blob on search
  would be costly.
- AppleScript message sending works best for recipients you've already
  exchanged messages with. Apple has progressively restricted Messages
  scripting on newer macOS versions.

## License

MIT — see [LICENSE](LICENSE).
