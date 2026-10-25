# apple-mcp

A native-Swift [Model Context Protocol](https://modelcontextprotocol.io) server
that exposes macOS **Calendar**, **Reminders**, **Contacts**, **Photos**, and
**Messages** to AI agents (Claude Code, Claude Desktop, etc.). No Node, no
Python, no shell glue — one statically-linked Swift binary.

## Install

### Homebrew (recommended)

```sh
brew install gheydon/apple-mcp/apple-mcp
```

Installs a notarized universal (`arm64 + x86_64`) binary at
`$(brew --prefix)/bin/apple-mcp`.

### Download a pre-built binary

Grab the latest tarball from the
[Releases page](https://github.com/gheydon/apple-mcp/releases) — it contains a
notarized universal binary that runs on Intel and Apple Silicon Macs.

```sh
tar -xzf apple-mcp-*-macos.tar.gz
mv apple-mcp /usr/local/bin/   # or wherever
```

### Build from source

Requires Swift 6.0+ (Xcode 16+) on macOS 14+.

```sh
git clone https://github.com/gheydon/apple-mcp.git
cd apple-mcp
swift build -c release
```

The binary lands at `.build/release/apple-mcp`.

## Tools

| Tool | Description |
| --- | --- |
| `calendar_list_calendars` | List all calendars on the system |
| `calendar_list_events` | List events in a date range |
| `calendar_create_event` | Create a new event |
| `reminders_list_lists` | List reminder lists |
| `reminders_list` | List reminders, filter by list/status/due date |
| `reminders_create` | Create a reminder |
| `reminders_complete` | Mark a reminder complete |
| `contacts_search` | Search contacts by name, phone or email; returns phones, emails, addresses, URLs, birthday |
| `contacts_create` | Create a new contact |
| `photos_list_albums` | List user-created and non-empty smart albums |
| `photos_list_people` | List named people recognized by Photos, with IDs and asset counts |
| `photos_list_pets` | List named pets recognized by Photos, with IDs and asset counts |
| `photos_search` | Filter photos by date range, favorites, media type, album, person, and/or pet |
| `photos_export` | Save a full-resolution photo or video to disk |
| `photos_view` | Return a downsized JPEG of an image asset as inline image content |
| `messages_list_chats` | List recent iMessage/SMS chats |
| `messages_recent` | Recent messages, optionally per chat |
| `messages_search` | Substring search over the `text` column |
| `messages_send` | Send a message via Messages.app |

### People and pets

`photos_list_people` and `photos_list_pets` return each named identity's `id`,
`name`, `display_name`, `kind`, and `photo_count`, optionally filtered by a
`query` substring. Pass a name or `id` to `photos_search`:

```json
{"person": "Alex Smith", "pet": "Milo", "after": "2026-01-01", "limit": 20}
```

Names match exactly, ignoring case and diacritics; duplicate names match every
identity with that name. Combining `person` and `pet` returns assets containing
both, and `limit` applies after filtering. Photos must already have recognized
and named the person or pet.

These tools read the System Photo Library's SQLite database (read-only), so
they need full Photos access and may need Full Disk Access.

## Wire into Claude Code / Claude Desktop

### Automatic (recommended)

After installing, run:

```sh
apple-mcp register
```

It detects which MCP hosts you have installed (Claude Desktop, Claude Code),
prints what it would change, asks for confirmation per host, and adds an
`apple` entry to each `mcpServers` block pointing at the running binary.
Existing entries for other MCP servers are preserved; the prior config is
backed up to `<config>.bak`.

Flags:

- `--host claude-desktop|claude-code` — target only one host
- `--yes` / `-y` — non-interactive; assume yes
- `--path <path>` — register a specific binary location instead of the
  running executable

To remove the entry later, run `apple-mcp unregister` (same flags apply).

### Manual

If you'd rather edit the config yourself, add to your MCP host config
(`claude_desktop_config.json` or `~/.claude.json`):

```json
{
  "mcpServers": {
    "apple": {
      "command": "/opt/homebrew/bin/apple-mcp"
    }
  }
}
```

On Intel Macs the Homebrew path is `/usr/local/bin/apple-mcp`. If you built
from source, point at `/absolute/path/to/apple-mcp/.build/release/apple-mcp`.

## Permissions

macOS will prompt for these the first time each tool group is used:

1. **Calendar** — *System Settings → Privacy & Security → Calendar*
2. **Reminders** — *System Settings → Privacy & Security → Reminders*
3. **Contacts** — *System Settings → Privacy & Security → Contacts*
4. **Photos** — *System Settings → Privacy & Security → Photos*
5. **Automation → Messages** — granted on first `messages_send`
6. **Full Disk Access** — must be granted *manually* to the parent process
   (Terminal, iTerm, Claude Desktop) to read `~/Library/Messages/chat.db`.
   People/pet discovery and search may also need this to read Photos' local
   database and library preferences.

## How it works

| Concern | Implementation |
| --- | --- |
| Calendar / Reminders | `EventKit` (`EKEventStore`, `requestFullAccessToEvents` / `requestFullAccessToReminders`) |
| Contacts | `Contacts` framework (`CNContactStore`) |
| Photos | `PhotoKit` (`PHPhotoLibrary`, `PHAsset`, `PHImageManager`); thumbnails JPEG-encoded via `NSBitmapImageRep` |
| Photos people / pets | Read-only `SQLite3` queries of system-library identities and face associations, followed by PhotoKit asset filtering |
| Messages reading | Direct `SQLite3` access to `~/Library/Messages/chat.db` |
| `attributedBody` decoding | Hand-written typedstream scanner — modern Messages stores body text in an `NSArchiver`-format BLOB, not in the `text` column |
| Messages sending | `NSAppleScript` driving Messages.app (Apple provides no public Swift API for sending iMessages) |
| MCP protocol | Official [`modelcontextprotocol/swift-sdk`](https://github.com/modelcontextprotocol/swift-sdk) |

## Known limitations

- People/pet search relies on Photos' undocumented database schema. Required
  tables and columns are checked before querying; unsupported schemas produce
  an explicit error. Hidden and deleted assets are excluded from identity
  discovery and search.
- `messages_search` only matches the `text` column. Messages whose body lives
  solely in `attributedBody` are not matched. Decoding every blob on search
  would be costly.
- AppleScript message sending works best for recipients you've already
  exchanged messages with. Apple has progressively restricted Messages
  scripting on newer macOS versions.

## Releasing

```sh
NOTARY_PROFILE=apple-mcp-notary scripts/release.sh 0.2.0
```

Builds a universal binary, signs it with a Developer ID Application identity,
notarizes via the named keychain profile, and writes
`dist/apple-mcp-0.2.0-macos.tar.gz` ready to upload to a GitHub release.

## License

GPL-2.0 — see [LICENSE](LICENSE).
