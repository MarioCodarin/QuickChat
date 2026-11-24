<p align="center">
  <img src="docs/logo.png" width="128" alt="QuickChat logo">
</p>

<h1 align="center">QuickChat</h1>

<p align="center">
  A tiny menu-bar panel for asking an AI one or two quick questions.<br>
  Works with any OpenAI-compatible endpoint. Native, ~1.4 MB, no Electron.
</p>

---

Press **⌥Space** from anywhere, type, hit **⏎**, read the answer as it streams in, press **Esc**. That's the whole app.

## Features

- **Floating glass panel** that opens over whatever you're doing and never steals focus from your current app
- **Bring your own endpoint.** Paste an [opencode](https://opencode.ai)-style config, or add a base URL, key and model IDs by hand
- **Streaming answers** with inline markdown and a collapsible "Thought process" for reasoning models
- **Reasoning effort picker** (low / high / max…) for models whose config defines `variants`
- **Personal touches:** a greeting with your name, six accent colors, light / dark / auto
- **Private by design:** API keys live in the macOS Keychain, and nothing is sent anywhere except the endpoint you chose

## Install

You need macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.

```sh
git clone https://github.com/MarioCodarin/QuickChat.git
cd QuickChat
./scripts/build.sh          # produces build/QuickChat.app
cp -R build/QuickChat.app /Applications/
open /Applications/QuickChat.app
```

The app is ad-hoc signed, not notarized. If macOS refuses to open it the first time, right-click it in Finder and choose **Open**, or run `xattr -dr com.apple.quarantine /Applications/QuickChat.app`.

## Add a model

On first launch the panel opens on the settings screen. Paste a config like this and press **Import config**:

```json
{
  "model": "myhost/my-model",
  "provider": {
    "myhost": {
      "name": "My Host",
      "options": { "baseURL": "https://api.example.com/v1" },
      "models": {
        "my-model": {
          "name": "My Model",
          "variants": {
            "low":  { "reasoningEffort": "low" },
            "high": { "reasoningEffort": "high" },
            "medium": { "disabled": true }
          }
        }
      }
    }
  }
}
```

Then paste your API key into the endpoint's key field. Comments and trailing commas are fine, and so is pasting just the `provider` part. Prefer a form? **Add manually** takes a name, base URL, key and a comma-separated list of model IDs (so `http://localhost:11434/v1` for Ollama works too).

QuickChat calls `POST {baseURL}/chat/completions` with `stream: true`. If you pick an effort level, it sends it as `reasoning_effort`.

## Shortcuts

| Key | Action |
| --- | --- |
| ⌥Space | Show / hide the panel (also: click the menu-bar icon) |
| ⏎ | Send |
| ⇧⏎ or ⌥⏎ | New line |
| ⌘N | New chat |
| ⌘, | Settings |
| Esc | Close (or leave settings) |

Right-click the menu-bar icon for Settings and Quit.

## Where things are stored

| What | Where |
| --- | --- |
| API keys | macOS Keychain (service `io.github.mariocodarin.quickchat`) |
| Endpoints and models | `~/Library/Application Support/QuickChat/endpoints.json` |
| Name, accent, theme, selected model | `UserDefaults` |

Only the current conversation is kept in memory. Closing the app forgets it.

## Development

```sh
swift run selftest          # config import, streaming parser, store (no Xcode needed)
./scripts/build.sh          # release build + QuickChat.app
./scripts/make-icon.sh      # re-render the icon from Resources/icon.svg (needs librsvg)
```

```
Sources/QuickChatCore/   models, config importer, streaming client, Keychain, store
Sources/QuickChat/       menu-bar shell, floating panel, hotkey, SwiftUI views
Tests/SelfTest/          dependency-free test executable
```

**Build note:** on some Command-Line-Tools-only installs the newest SDK is missing the SwiftUI macro plugin (`plugin for module 'SwiftUIMacros' not found`). `build.sh` detects this and retries with the next-older SDK in `/Library/Developer/CommandLineTools/SDKs`. XCTest and Swift Testing are missing there too, which is why the tests are a plain executable.

## License

[MIT](LICENSE)
