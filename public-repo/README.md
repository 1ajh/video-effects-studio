<p align="center"><img src="https://raw.githubusercontent.com/1ajh/srle-studio/main/logo.png" width="96" alt=""></p>

# SRLE Studio

Sparta remixes and logo-editing effects on your computer. Get it at **[srle.ajh.wtf](https://srle.ajh.wtf)**: the app needs a license key from there to unlock.

This repository holds what SRLE Studio reads from the internet, in the open:

- **[Releases](https://github.com/1ajh/srle-studio/releases)**: the Windows, macOS and Linux downloads (they unlock with your key). The app checks here for updates.
- **[`bases/`](bases)**: the Sparta base library the app searches (`catalog.json`: where each base is published and who made it) and checked transcriptions of bases (`transcriptions/`), which the app downloads so remixes follow those bases exactly.
- **[Issues](https://github.com/1ajh/srle-studio/issues)**: bug reports, and fixed base transcriptions sent from the app.

## Sending a fixed base transcription

In the app, fix a base's sections, hits or drums, then press **Send your fixes**. It saves a `.sparta.json` file and opens a filled-in issue here: drag the file into it. Once it's checked, a maintainer labels the issue `transcription-approved`, a workflow opens a pull request adding it to `bases/` with your credit, and everyone using the app gets it.

## Reporting a bug

Open an [issue](https://github.com/1ajh/srle-studio/issues/new/choose) with what you did, what happened and your system. No license keys in issues, please.

## Licenses

See [LICENSE.md](LICENSE.md).
