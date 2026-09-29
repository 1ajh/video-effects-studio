# Video Effects Studio

A desktop studio for **logo-editing style video effects**: G-Majors, vocoders, CoNfUsIoN, Low Voice, Luig Group, Sparta pitches, glitches, and 140+ more. Preview any effect on your clip instantly, then render it, or build a **compilation** that plays your clip through effect after effect, like the classic "X in 40 effects" videos.

![Platforms](https://img.shields.io/badge/Windows%20%7C%20macOS%20%7C%20Linux-desktop-7C5CFF)
![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter)
![License](https://img.shields.io/badge/License-MIT-green)
[![CI](https://github.com/1ajh/video-effects-studio/actions/workflows/ci.yml/badge.svg)](https://github.com/1ajh/video-effects-studio/actions/workflows/ci.yml)

## What's inside

- **148 effects in 9 categories**, every one rendered through real FFmpeg in CI:
  - **Logo Editing**: recipes documented by the logo-editing community (Low Voice, Luig Group, CoNfUsIoN, Devil's Blast, Chorded, Crying, Angry, Weird Code, Awake, Hitting, Sponge, Pitch Black, Crazy Diamond, V-Major, You Wiggled, DMA Diamond Major and more)
  - **G-Majors & Chords**: G-Major 2 / 4, the NotSoBot G-Majors, and a **Chord Builder** where you type the pitch of every duplicated track
  - **Vocoders & Robots**: real robotized voices (FFT phase vocoding), stacked into chords with the matching looks. The old version only tinted the video.
  - **Color, Distortion, Glitch, Audio, Time & Speed**: mirrors, swirl, pinch, bulge, kaleidoscope, CRT, VHS, RGB split, datamosh melt, 8-bit, deep fried, vaporwave, bass boost, earrape, 8D audio, reverse, boomerang, stutter, nightcore…
  - **YTPMV tools**: a real **Sparta Sequencer** (plays one sample as a melody), **Beat Chop** ("1 1 2 1 3 3 4 4") and **Pitch Ladder**
- **Before / after preview**: every effect is rendered as a short preview automatically. Watch it on its own or side by side with the original.
- **Effect thumbnails**: the effect list shows each effect applied to *your* clip.
- **Compilations**: effects play one after another in order. Add effects one by one, a whole category, **every effect**, or **N random** ones; shuffle and drag to reorder. Optionally play the original first, and label each segment with a **name overlay** or a **title card**. Each item keeps its own settings.
- **Trim** any range before rendering, with I/O shortcuts at the playhead.
- **Export** MP4 (H.264/AAC, plays in Discord etc.), WebM, GIF, MP3 or WAV, at High / Balanced / Small quality with an optional resolution cap.
- **Batch**: render one effect over every loaded clip.
- **Presets, favorites and recents**.
- **Custom effects**: write your own FFmpeg filter chains, test them in place, and use them anywhere (compilations included).
- **Render queue** with progress, ETA, cancel, "show in folder", and a persistent history.

> Loud effects are loud on purpose: authentic volume, no limiter. They carry a 🔊 badge.

## Download

Grab the latest build from [Releases](https://github.com/1ajh/video-effects-studio/releases). FFmpeg is bundled, so there's nothing else to install.

| Platform | File | Notes |
|---|---|---|
| Windows 10/11 | `VideoEffectsStudio-windows.zip` | Unzip and run `video_effects_studio.exe` |
| macOS 12+ | `VideoEffectsStudio-macos.dmg` | Unsigned: right-click → Open the first time |
| Linux (x64) | `VideoEffectsStudio-linux.tar.gz` | Needs GTK 3 and **libmpv** for in-app playback (`sudo apt install libmpv2`) |

Rendering runs FFmpeg locally, so phones and browsers can't do it. The web/mobile builds just show the effect list and a download link.

## Using it

1. **Add a clip**: drag it anywhere onto the window, or press `Ctrl+O`.
2. **Pick an effect** on the left. A preview renders on its own (`Ctrl+P` to force it).
3. Tweak **parameters** in the inspector on the right, and set the **output** format and folder below them.
4. **Render** (`Ctrl+Enter`). Jobs appear in the queue (`Ctrl+Q`).

**Compilation mode** (`Ctrl+2`): add effects with the ➕ button, double-click, or `Ctrl+D`, or use *All effects / Add category / Random* in the dock at the bottom. Click a card to edit that item, drag to reorder, and choose *Original first* and a label style. Then render.

### Shortcuts

| Keys | Action |
|---|---|
| `Ctrl+O` | Add clips |
| `Ctrl+Enter` | Render |
| `Ctrl+P` | Preview now |
| `Space` / `Home` | Play-pause / back to start |
| `I` / `O` | Set trim in / out |
| `Ctrl+F`, `↑` `↓` | Search / step through effects |
| `Ctrl+D` | Add effect to the compilation |
| `Ctrl+1` / `Ctrl+2` | Single effect / Compilation mode |
| `1` `2` `3` | Original / Effect / Split view |
| `Ctrl+H`, `Ctrl+,`, `F1` | History, Settings, Help |

## Building from source

Requirements: Flutter 3.47+ and FFmpeg on your `PATH` (or pick it in Settings → FFmpeg).

```bash
flutter pub get
flutter run -d windows   # or macos / linux
```

Linux build dependencies:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libmpv-dev ffmpeg
```

### Tests

```bash
flutter test --exclude-tags ffmpeg   # unit + widget tests (~500)
flutter test --tags ffmpeg           # renders every effect with real FFmpeg
VFX_FFMPEG=/path/to/ffmpeg flutter test --tags ffmpeg   # against a specific build
```

The FFmpeg suite renders every effect on a clip with audio and on an odd-sized clip without audio. It also covers every output format, all compilation label modes, skipped-segment handling, previews and thumbnails. CI runs it against Ubuntu's FFmpeg 6.1, and it also passes on current FFmpeg master.

## How effects work

Effects are declared in `lib/core/effects/library/`. Each effect gets a label for the incoming stream and returns the label of its output, building a `-filter_complex` graph with shared blocks (`lib/core/ffmpeg/blocks.dart`): pitch shifting without rubberband, pitch chords, mirrors, waves, swirl, radial pinch/bulge, TV simulator, light rays, gradient maps and more.

```dart
Effect(
  id: 'luig_group',
  name: 'Luig Group',
  description: 'HSL Adjust "Invert Color" hue flip with the pitch set to −1.',
  category: EffectCategory.logoEditing,
  video: vf(hslInvert),
  audio: af(pitch(-1)),
),
```

The command builder takes care of the boring parts: argument lists (no shell quoting), trimming, even frame sizes, `yuv420p`, 48 kHz stereo, clips without audio, exact segment lengths for compilations, and output encoders.

```
lib/
  core/        effects, FFmpeg command building, rendering (pure Dart, fully tested)
  state/       controllers (project, editor, compilation, preview, queue, library, settings)
  ui/          the editor: browser, preview, inspector, compilation dock, queue, pages
```

## Credits

- Effect recipes are inspired by the [Logo Editing Wiki](https://logo-editing.fandom.com/wiki/Category:Effects) community and the original NotSoBot tags by **AJH**
- [FFmpeg](https://ffmpeg.org), [Flutter](https://flutter.dev), [media_kit](https://github.com/media-kit/media-kit), [Inter](https://rsms.me/inter/) (SIL OFL)

MIT License, see [LICENSE](LICENSE).
