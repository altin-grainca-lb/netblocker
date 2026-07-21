# NetBlocker

A tiny macOS menu-bar app that blocks other apps from phoning home — no
kernel extensions, no drivers, no Apple Developer account required.

Pick an app → NetBlocker scans its binaries for the servers it talks to →
tick the domains you want gone → they stop resolving, system-wide, via
`/etc/hosts`. Flip the switch to unblock at any time.

![menu bar app](https://img.shields.io/badge/macOS-13%2B-blue) ![license](https://img.shields.io/badge/license-MIT-green)

## Install

1. Download the latest `NetBlocker-x.y.z.dmg` from
   [Releases](../../releases), open it, and drag **NetBlocker** to
   **Applications**.
2. The app is ad-hoc signed (no paid developer certificate), so the first
   launch needs one extra step:
   - **macOS 15 (Sequoia) and later:** open the app once (it will be
     blocked), then go to **System Settings → Privacy & Security**, scroll
     down, and click **Open Anyway**.
   - **macOS 13–14:** right-click the app in Applications and choose
     **Open**, then confirm.
   - Or from a terminal: `xattr -d com.apple.quarantine /Applications/NetBlocker.app`
3. Look for the shield icon in your menu bar.

## Usage

- Click **+** and choose an app from `/Applications`.
- NetBlocker scans the app's executables (including Electron `app.asar`
  archives) and lists every domain baked into them, most frequent first.
  Domains matching the app's name are pre-selected.
- Click **Block**. macOS asks for your administrator password once — that's
  the standard system dialog NetBlocker uses to update `/etc/hosts` and
  flush the DNS cache.
- Use the row toggle to block/unblock, the pencil to change domains, the
  trash to remove (and unblock) an app.
- **Launch at login** can be enabled with the checkbox at the bottom of the
  popover (uses the system login-items mechanism, no daemons).
- If a DNS proxy (NextDNS, AdGuard, Cloudflare WARP, …) is running, or a
  blocked domain still resolves to a real address, NetBlocker shows a
  warning banner — that's your signal the proxy is bypassing `/etc/hosts`
  and the domains should go in the proxy's own denylist instead.

## How it works

For each blocked app, NetBlocker appends a clearly marked section to
`/etc/hosts` mapping the selected domains to `0.0.0.0` (and `::` for IPv6):

```
# >>> NetBlocker[com.example.someapp] >>>
0.0.0.0 api.example.com
:: api.example.com
# <<< NetBlocker[com.example.someapp] <<<
```

Unblocking removes exactly that section and leaves the rest of the file
untouched. Nothing runs in the background — no daemons, no network
extensions. The hosts file is the whole mechanism.

## Limitations (honest ones)

- **System-wide blocks.** `/etc/hosts` affects every process, not just the
  chosen app. Blocking a shared service (analytics providers, license
  servers like LemonSqueezy, GitHub) affects other apps too — the domain
  list is fully in your control, so choose accordingly.
- **DNS proxies and network filters bypass it.** DNS proxies (NextDNS,
  AdGuard), VPN MagicDNS, and corporate security network extensions
  (Microsoft Defender for Endpoint, Zscaler, Cisco Umbrella) resolve names
  through their own path and ignore `/etc/hosts` for any domain that exists
  in public DNS. NetBlocker functionally probes your blocked domains and, if
  a block isn't taking effect, shows a banner naming the likely active
  filter. On MDM-managed machines these filters usually **cannot be
  disabled**, so `/etc/hosts` blocking won't work for live domains there —
  that needs a real content-filter firewall with the Network Extension
  entitlement, which your IT controls.
- **Determined apps can evade it.** Hardcoded IPs or an app doing its own
  DNS-over-HTTPS won't be stopped by hosts entries. For that you need a real
  content-filter firewall ([LuLu](https://objective-see.org/products/lulu.html),
  Little Snitch), which requires Apple's Network Extension entitlement.
- **License checks.** Blocking an app's licensing domain can make it think
  the license is invalid. Unblock, relaunch, re-block if that happens.

## Build from source

Requires Swift 5.9+ (Xcode Command Line Tools are enough):

```sh
swift scripts/make-icon.swift   # only if assets/AppIcon.icns is missing
./scripts/build-app.sh          # -> dist/NetBlocker.app
./scripts/make-dmg.sh           # -> dist/NetBlocker-<version>.dmg
```

## Uninstall

Toggle all apps off (removes their hosts sections), quit NetBlocker, delete
`/Applications/NetBlocker.app` and `~/Library/Application Support/NetBlocker`.
Leftover sections can also be deleted from `/etc/hosts` by hand — they're the
lines between `# >>> NetBlocker[...] >>>` and `# <<< NetBlocker[...] <<<`.

## License

MIT
