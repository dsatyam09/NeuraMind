# NeuraMind

Ambient focus intelligence for ADHD brains.

NeuraMind is a macOS menu bar app designed to help people with ADHD stay on track throughout their workday. It quietly watches your screen activity, understands what you're working on, and surfaces the right context at the right moment — without asking you to check a dashboard or switch your attention.

**What it does:**
- Tracks what you're working on across all your apps, continuously and automatically
- Shows a colored border around your screen that reflects your current focus state in real time — no glancing required
- Reminds you where you left off when you return from a drift period
- Offers a daily planning and wind-down ritual powered by Claude, grounded in what you actually did
- Lets you enrich any AI prompt with relevant context from your recent screen activity

No setup rituals. No manual logging. Just open it and work.

---

## System Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac
- [Claude Code CLI](https://claude.ai/code) installed and signed in — NeuraMind uses it for all AI features

---

## Privacy

**Your data never leaves your Mac.**

All screen captures, summaries, and activity records are stored locally in a SQLite database at `~/Library/Application Support/NeuraMind/`. Nothing is sent to any server or cloud service operated by this app.

AI features work by running the `claude` CLI directly on your machine using your own Claude Code session. This means:

- No API keys required
- No data routed through third-party servers by NeuraMind itself

**Important:** When NeuraMind calls Claude, your screen content is passed to the Claude CLI, which is subject to Anthropic's data usage policies. If you do not want your data used for model training, make sure you have opted out in your [Anthropic account settings](https://console.anthropic.com/) before using NeuraMind.

Raw screen captures are automatically deleted after 72 hours.

---

## Installation

1. Download the latest `NeuraMind.app` from the [Releases](../../releases) page.
2. Move it to your `/Applications` folder.
3. Open it. macOS may ask you to confirm opening an app from an unidentified developer — click **Open**.
4. Grant **Accessibility** permission when prompted. This is required for NeuraMind to read window titles and app metadata. Without it, the app will not start capturing.
5. Make sure the `claude` CLI is installed and you are signed in:
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude login
   ```

NeuraMind lives in your menu bar. There is no Dock icon.

---

## Building from Source

**Requirements:** Swift 6.0+, Xcode 16+

```bash
git clone https://github.com/your-org/neuramind
cd neuramind

# Debug build and run
swift build
make run

# Optimized release build
make release

# Create app bundle
make bundle

# Install to /Applications/NeuraMind.app
make install-app
```

---

Built by **Saturday Club**

MIT License
