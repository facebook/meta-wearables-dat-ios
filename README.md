# Meta Wearables Device Access Toolkit for iOS

[![Swift Package](https://img.shields.io/badge/Swift_Package-0.7.0-brightgreen?logo=swift&logoColor=white)](https://github.com/facebook/meta-wearables-dat-ios/tags)
[![Docs](https://img.shields.io/badge/API_Reference-0.7-blue?logo=meta)](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.7)

The Meta Wearables Device Access Toolkit enables developers to utilize Meta's AI glasses to build hands-free wearable experiences into their mobile applications.
By integrating this SDK, developers can reliably connect to Meta's AI glasses and leverage capabilities like video streaming and photo capture.

The Wearables Device Access Toolkit is in developer preview.
Developers can access our SDK and documentation, test on supported AI glasses, and create organizations and release channels to share with test users.

## Documentation & Community

Find our full [developer documentation](https://wearables.developer.meta.com/docs/develop/) on the Wearables Developer Center.

You can find an overview of the Wearables Developer Center [here](https://wearables.developer.meta.com/).
Create an account to stay informed of all updates, report bugs and register your organization.
Set up a project and release channel to share your integration with test users.

For help, discussion about best practices or to suggest feature ideas visit our [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

See the [changelog](CHANGELOG.md) for the latest updates.

## Including the SDK in your project

The easiest way to add the SDK to your project is by using Swift Package Manager.

1. In Xcode, select **File** > **Add Package Dependencies...**
1. Search for `https://github.com/facebook/meta-wearables-dat-ios` in the top right corner
1. Select `meta-wearables-dat-ios`
1. Set the version to one of the [available versions](https://github.com/facebook/meta-wearables-dat-ios/tags)
1. Click **Add Package**
1. Select the target to which you want to add the packages
1. Click **Add Package**

## Developer Terms

- By using the Wearables Device Access Toolkit, you agree to our [Meta Wearables Developer Terms](https://wearables.developer.meta.com/terms),
  including our [Acceptable Use Policy](https://wearables.developer.meta.com/acceptable-use-policy).
- By enabling Meta integrations, including through this SDK, Meta may collect information about how users' Meta devices communicate with your app.
  Meta will use this information collected in accordance with our [Privacy Policy](https://www.meta.com/legal/privacy-policy/).
- You may limit Meta's access to data from users' devices by following the instructions below.

### Opting out of data collection

To configure analytics settings in your Meta Wearables DAT iOS app, you can modify your app's `Info.plist` file using either of these two methods:

**Method 1:** Using Xcode (Recommended)

1. In Xcode, select your app target in the **Project** navigator
1. Go to the **Info** tab
1. Navigate to **Custom iOS Target Properties**  and find the `MWDAT` key
1. Add a new key under `MWDAT` called `Analytics` of type `Dictionary`
1. Add a new key to the `Analytics` dictionary called `OptOut` of type `Boolean` and set the value to `YES`

**Method 2:** Direct XML editing

Add or modify the following in your `Info.plist` file.

```XML
<key>MWDAT</key>
<dict>
    <key>Analytics</key>
    <dict>
        <key>OptOut</key>
        <true/>
    </dict>
</dict>
```

**Default behavior:** If the `OptOut` key is missing or set to `NO`/`<false/>`, analytics are enabled
(i.e., you are **not** opting out). Set to `YES`/`<true/>` to disable data collection.

**Note:** In other words, this setting controls whether or not you're opting out of analytics:

- `YES`/`<true/>` = Opt out (analytics **disabled**)
- `NO`/`<false/>` = Opt in (analytics **enabled**)

## AI-Assisted Development

This repository ships one public DAT knowledge base in two first-class formats:

| Tool | Public artifact | Recommended setup |
|------|-----------------|-------------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | `.claude-plugin/marketplace.json` + `plugins/mwdat-ios/.claude-plugin/plugin.json` | Add this GitHub repo as a marketplace, then install `mwdat-ios` |
| Codex | `plugins/mwdat-ios/.codex-plugin/plugin.json` | Add this GitHub repo as a Codex marketplace |
| [GitHub Copilot](https://github.com/features/copilot) | `.github/copilot-instructions.md` | Auto-loaded by Copilot in VS Code |
| [Cursor](https://cursor.sh/) | `.cursor/rules/*.mdc` | Auto-loaded with glob-based triggers |
| AGENTS.md-compatible tools | `AGENTS.md` | Portable fallback for agents that read `AGENTS.md` |
| MCP-compatible editors | `https://mcp.facebook.com/wearables_dat` | Connect as a remote HTTP MCP server |

Claude installs from the plugin payload under `plugins/`. Codex adds this repository as a plugin marketplace. Copilot, Cursor, and `AGENTS.md` readers use the native file-based artifacts at repo root.

### Claude Code

```bash
claude plugin marketplace add facebook/meta-wearables-dat-ios
claude plugin install mwdat-ios@mwdat-ios-marketplace
```

Or use the helper script:

```bash
./install-skills.sh claude
```

### Codex

```bash
git clone https://github.com/facebook/meta-wearables-dat-ios.git
cd meta-wearables-dat-ios
codex plugin marketplace add .
```

Or use the helper script:

```bash
./install-skills.sh codex
```

### Other tool installs

Use the installer when you want the repo-native file surfaces for other tools:

```bash
./install-skills.sh copilot   # .github/copilot-instructions.md
./install-skills.sh cursor    # .cursor/rules/*.mdc
./install-skills.sh agents    # AGENTS.md
./install-skills.sh all       # Claude/Codex when available, plus Copilot/Cursor/AGENTS.md
```

Or run the helper remotely:

```bash
curl -sL https://raw.githubusercontent.com/facebook/meta-wearables-dat-ios/main/install-skills.sh | bash
```

### What's included

- **Getting started** — SDK setup, SPM integration, Info.plist configuration
- **Camera streaming** — Stream, video frames, resolution/frame rate, photo capture
- **MockDevice testing** — Test without physical glasses using MockDeviceKit
- **Session lifecycle** — Device session states, pause/resume, availability
- **Permissions & registration** — App registration, camera permission flows
- **Debugging** — Common issues, Developer Mode, version compatibility
- **Sample app guide** — Building a complete DAT app

For static reference context, point your AI tool at the [llms.txt endpoint](https://wearables.developer.meta.com/llms.txt?full=true). For live documentation search in MCP-compatible editors, connect `https://mcp.facebook.com/wearables_dat` and use `search_dat_docs`.

## License

See the [LICENSE](LICENSE) file.
