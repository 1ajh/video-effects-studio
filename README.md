# Video Effects Studio

A desktop studio for **logo-editing style video effects**: G-Majors, vocoders, CoNfUsIoN, Low Voice, Luig Group, Sparta pitches, glitches, and 140+ more. Preview any effect on your clip instantly, then render it, or build a **compilation** that plays your clip through effect after effect, like the classic "X in 40 effects" videos. And the **Sparta Remix Generator** turns any video of someone talking into a full, mixed and mastered Sparta remix, video included.

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
- **Sparta Remix Generator** (see below)
- **Trim** any range before rendering, with I/O shortcuts at the playhead.
- **Export** MP4 (H.264/AAC, plays in Discord etc.), WebM, GIF, MP3 or WAV, at High / Balanced / Small quality with an optional resolution cap.
- **Batch**: render one effect over every loaded clip.
- **Presets, favorites and recents**.
- **Custom effects**: write your own FFmpeg filter chains, test them in place, and use them anywhere (compilations included).
- **Render queue** with progress, ETA, cancel, "show in folder", and a persistent history.

## Sparta Remix Generator

The third mode (`Ctrl+3`) makes a Sparta remix the way the community does: a real base, followed exactly, with samples cut from your video. It goes in four steps: **Base → Source → Line → Generate**.

- **Base**
  - **Library**: 579 real bases you can search and download, each credited to its maker and linked to where it was published: Keaton's official Sparta Extended instrumental, the HADES BLACK, Francex and *Some Sparta Bases Archive* collections, single uploads, and the Sparta Archive FLP Remixes, whose bases come with their FL Studio projects (marked **Exact**).
  - **Your audio**: any base as MP3/WAV. Tempo, bar 1, the kicks, snares and hats, the hit notes (matched against every pitch pattern on the Sparta Remix Wiki, in every key) and the sections are worked out by listening. If the file is a library base, its checked transcription is used instead.
  - **Your project**: FL Studio `.flp`, FL Studio Mobile `.flm` or MIDI, with the base's audio (lined up automatically) or re-synthesized. The base's notes are read exactly; pick the hit/lead track if the automatic choice is wrong.
- **What the remix plays** (all from the base, nothing made up):
  - the **pitch sample** plays the base's own hit notes, hard-tuned to the base's root (or *Natural*, keeping the voice's wobble);
  - the **chorus words** play the wiki's word patterns: the standard chorus, DunDunDenDen's 1-2-3A-3B, the epicness and madness patterns, only in the sections that have them. The chorus is words only;
  - the **percussion** lands on the base's own kicks, snares and hats;
  - the **quote** (your whole line) opens the intro.
- **Source and line**: everything is cut from your sources. The app finds the spoken lines; you pick one and its words become the chorus samples, numbered in order (syllables of a word are 3A, 3B…). Play each word, drag the cuts between words, split, join or trim them. Nothing is layered from anywhere else unless you switch on the synth drum body (off by default: that would be a fake sample). Chorus Crisp is on by default.
- **Fix the base**: transcriptions from audio are drafts, so everything is editable: relabel, rename, split, merge or drag sections (the classics plus pre- and post-epicness), change the root, move or replace a section's hits with a wiki pattern, fix its kick/snare/hat, nudge beat 1. Fixes are kept per base. **Send your fixes** saves the transcription and opens a filled-in GitHub issue; approved ones are added to the catalog with your credit, for everyone.
- **Per section**: choose any of the wiki's word and pitch patterns (classics, freestyles, KingSpartaX37's madness and the rest), or type your own in wiki notation.
- **Random mode** (off by default) can use chorus freestyles, other pitch patterns, other samples per section and a different section layout. *Another take* re-rolls it.
- **Video**: the classic box grid by default: one box per sample (pitch, each word, kick, snare, hat), sized automatically (2×2, 3×3 or 4×4), flipping horizontally on every hit, black between hits, and the quote full screen. Every one of those is an option (grid size; which boxes flip and how; black, dimmed or held last frame; quote full screen, in its own box or as a title card), plus Modern, Chaos/YTPMV and Minimal styles.
- **Mix and export**: sampler transposition, choke per lane, a bus per lane, the base ducked under the quote, then a **Clean** (≈ −10 LUFS, −1 dB peak) or **Hot** master. Export the video (or MP3/WAV), plus optional **stems** (base, pitch, words, drums, quote) and **MIDI** (the sample chart and the base's notes).

> **Volume**: by default every render is level-matched to about −9 LUFS with a −1 dB peak (*Loud & consistent*). The effect's audio is measured first, then turned up or down, soft-clipped and limited, so quiet effects like vocoders come out as loud as the rest. Effects that are loud on purpose (🔊 badge) are never turned down. Choose *Standard* (−14 LUFS) or *As the effect makes it* under Output → Volume.

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

**Sparta Remix mode** (`Ctrl+3`): pick a base, add your sources, confirm the line, press **Generate remix**, review, then **Render remix**.

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
| `Ctrl+1` / `2` / `3` | Single effect / Compilation / Sparta Remix mode |
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
flutter test --exclude-tags ffmpeg   # unit + widget tests (~540)
flutter test --tags ffmpeg           # renders every effect and full Sparta remixes with real FFmpeg
VFX_FFMPEG=/path/to/ffmpeg flutter test --tags ffmpeg   # against a specific build
```

The FFmpeg suite renders every effect on a clip with audio and on an odd-sized clip without audio, and runs the whole Sparta pipeline (sources → line, words and samples → project, audio-only and library bases → mix → video in every visual style). It also covers every output format, all compilation label modes, skipped-segment handling, previews and thumbnails. CI runs it against Ubuntu's FFmpeg 6.1, and it also passes on current FFmpeg master.

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
    audio/     DSP: FFT, YIN, onsets, TD-PSOLA, filters, dynamics, synthesis
    sparta/    base catalog, wiki pattern library, FLP/FLM/MIDI readers, project and audio
               transcription, line & sample finder, enhancer, charter, mixer, visual renderer
  state/       controllers (project, editor, compilation, preview, queue, library, settings, sparta)
  ui/          the editor: browser, preview, inspector, compilation dock, Sparta workspace, queue, pages
```

## Credits

- Sparta patterns and section names come from the [Sparta Remix Wiki](https://spartaremix.fandom.com/wiki/Category:Sparta_Remix_Components) (CC BY-SA); bases are credited to their makers in the app
- Sparta techniques draw on the community's tools: PSOLA pitch correction as in Pet297's *PitchCorrector297*, Chorus Crisp and SlamShaper-style shaping from composition-cassidy's tools, and grid visuals like *Sparta Remix Visual Editor*
- Effect recipes are inspired by the [Logo Editing Wiki](https://logo-editing.fandom.com/wiki/Category:Effects) community and the original NotSoBot tags by **AJH**
- [FFmpeg](https://ffmpeg.org), [Flutter](https://flutter.dev), [media_kit](https://github.com/media-kit/media-kit), [Inter](https://rsms.me/inter/) (SIL OFL)

MIT License, see [LICENSE](LICENSE).
