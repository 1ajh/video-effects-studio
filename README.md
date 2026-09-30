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

The third mode (`Ctrl+3`) builds a complete Sparta remix from your sources, with no manual chopping:

- **Sample finding**: every source is analysed (pitch tracking, onsets, spectral shape, voicing) and ranked candidates are picked for each lane: a sustained vowel for **pitch**, a punchy syllable for the **chop**, low thumps / cracks / hisses for **kick, snare and hat**, and a clean spoken line for the **quote**. With several sources the lanes use different material and pitch/chop alternate between two voices.
- **Correction and enhancement**: pitch and chop samples are pitch-corrected to D with TD-PSOLA (octave-error repair, formant-preserving), and pitch samples are sustained so any note length works. Chops get a *Chorus Crisp* doubled attack, drum samples can be reinforced with a synthesized body, and everything is trimmed, de-clicked and normalized.
- **Bases**:
  - **Built-in**: three procedurally composed bases (Classic 140, Hyper 160, Venom 150 BPM) in the Sparta idiom: D Phrygian, the D–E♭–C–E♭ movement, and intro/quote, chorus, dundundenden, epicness, madness, awesomeness and outro sections. Toggle sections, pick a length, re-roll any section or the whole base.
  - **Your projects**: FL Studio `.flp`, FL Studio Mobile `.flm` and MIDI. Name the placeholder tracks (*Pitch*, *Chop*, *Quote*…) or map them in the app; with no sample lanes, a chart is composed over the project's own chords and drums, in the project's own scale. Sections come from patterns named after them (*perc intro*, *madness bassline*…), or else from where the project's parts change. Add the base's rendered audio (auto-aligned to the chart) or let the app re-synthesize the project.
  - **Any base audio**: tempo, the bar grid, the key and the chord of every bar are detected, and the chart is composed over them.
  - The readers and detectors are checked against real community bases from the Sparta FLP archive: 307 FL Studio projects from FL 10 to FL 21, FL Studio Mobile projects from old and new app versions, and base renders whose tempo and bar 1 are known from their projects.
- **Arrangement and mix**: sampler-style transposition on every chart note, monophonic choke, a bus per lane (EQ, compression, reverb, width), the base ducked under the quote, then a **Clean** (≈ −10 LUFS, −1 dB peak) or **Hot** (soft-clipped, loud) master.
- **Review before rendering**: play the mix, audition every sample, step through candidates, nudge sample edges, toggle a second sample per lane, adjust lane levels, re-roll sections. The preview updates on its own.
- **Visuals** in four presets (Classic grid, Modern, Chaos/YTPMV, Minimal): every hit cuts to its source footage at the transposed speed, with flips, hue shifts and punch-zooms per section. Audio-only sources become animated waveform cards.
- **Exports**: the video (or MP3/WAV), plus optional **stems** (base, pitch, chop, drums, quote) and **MIDI** (the sample chart, and the base parts when composed).

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

**Sparta Remix mode** (`Ctrl+3`): add sources, pick a base, press **Generate remix**, review, then **Render remix**.

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

The FFmpeg suite renders every effect on a clip with audio and on an odd-sized clip without audio, and runs the whole Sparta pipeline (sources → samples → built-in, MIDI and audio-only bases → mix → video in every visual preset). It also covers every output format, all compilation label modes, skipped-segment handling, previews and thumbnails. CI runs it against Ubuntu's FFmpeg 6.1, and it also passes on current FFmpeg master.

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
    sparta/    sample finder, enhancer, composer, FLP/FLM/MIDI readers, beat & chord
               analysis, arranger/mixer, visual renderer, pipeline engine
  state/       controllers (project, editor, compilation, preview, queue, library, settings, sparta)
  ui/          the editor: browser, preview, inspector, compilation dock, Sparta workspace, queue, pages
```

## Credits

- Sparta techniques draw on the community's tools: PSOLA pitch correction as in Pet297's *PitchCorrector297*, Chorus Crisp and SlamShaper-style shaping from composition-cassidy's tools, and grid visuals like *Sparta Remix Visual Editor*
- Effect recipes are inspired by the [Logo Editing Wiki](https://logo-editing.fandom.com/wiki/Category:Effects) community and the original NotSoBot tags by **AJH**
- [FFmpeg](https://ffmpeg.org), [Flutter](https://flutter.dev), [media_kit](https://github.com/media-kit/media-kit), [Inter](https://rsms.me/inter/) (SIL OFL)

MIT License, see [LICENSE](LICENSE).
