# Annotake

Annotake is a Mac menu-bar app for showing your coding agent exactly what happened. Double-tap Right ⌘, reproduce a bug, and drag the card it gives you into Claude Code, Cursor, or ChatGPT: one screenshot per step, each captioned with what you clicked.

This repo holds the app's releases and its installer only; there's no source code here.

## Install

[Download Annotake.dmg](https://github.com/fayzan123/annotake-releases/releases/latest/download/Annotake.dmg), open it, and drag Annotake to Applications.

Or paste this into Terminal:

```
curl -fsSL https://raw.githubusercontent.com/fayzan123/annotake-releases/main/install.sh | sh
```

It downloads the latest release, checks its signature, puts Annotake in your Applications folder, and opens it.

Annotake needs macOS 15 or later, on Apple silicon or Intel. It updates itself.

## First run

Annotake shows what it does, then asks for three permissions, one at a time:

- **Accessibility**, so it can name the buttons you click, and keep ⌘ out of your clicks while you hold the key.
- **Input Monitoring**, so it can notice Right ⌘, and your clicks and keys while you record. It never records what you type.
- **Screen Recording**, so it can capture your screen while you record.

macOS turns on Input Monitoring and Screen Recording only after a relaunch, so Annotake offers Quit & Reopen and comes back where it was. Then a practice run: double-tap Right ⌘, click through something, double-tap again, and drag the card into the window. Holding Right ⌘ works too, for quick ones, and Right ⌘ + Esc cancels.

## Privacy

Nothing you record leaves your Mac. Recordings stay in `~/Pictures/Annotake`, and move to the Trash after 30 days.

Annotake checks for updates once a day, and that check sends only its version.

## Feedback

Choose **Send Feedback…** in Annotake's menu-bar menu. It opens an email to Annotake's developer with a short report attached: the app and macOS versions, which permissions are on, the recent log, and the latest crash report if there is one. The log never contains button names, window titles, or keys, and nothing is sent until you send the email.

## Uninstall

Quit Annotake from its menu-bar icon and drag it from Applications to the Trash. To remove its permissions as well, run:

```
tccutil reset All com.fayzanmalik.annotake
```
