# Third-party notices

SRLE Studio is © AJH, all rights reserved. It comes with, or uses, the
following work by others, under their own licenses.

## FFmpeg

SRLE Studio renders with FFmpeg, which comes as separate programs next to it
(`ffmpeg` and `ffprobe`; inside `SRLE Studio.app/Contents/MacOS` on a Mac).
SRLE Studio runs them as programs; it doesn't link to them.

FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.
These builds include GPL parts (such as x264 and x265), so they are licensed
under the **GNU General Public License, version 3 or later**:
<https://www.gnu.org/licenses/gpl-3.0.html>. You may use, change and share
them under that license, separately from SRLE Studio.

Where these exact builds come from, with their build scripts and the FFmpeg
version they were made from (`ffmpeg -version` prints it):

- Windows and Linux: the `ffmpeg-master-latest-win64-gpl` and
  `ffmpeg-master-latest-linux64-gpl` builds by BtbN,
  <https://github.com/BtbN/FFmpeg-Builds>
- macOS: the release builds by Martin Riedl, <https://ffmpeg.martin-riedl.de>

FFmpeg's own source code is at <https://ffmpeg.org/download.html> and
<https://git.ffmpeg.org/ffmpeg.git>.

**Written offer:** for three years from when you got this copy of SRLE Studio,
AJH will give anyone who asks the complete corresponding source code of the
FFmpeg programs included with it, for no more than the cost of sending it.
Ask through <https://srle.ajh.wtf/contact>.

## Inter

The app's typeface is Inter, © 2016 The Inter Project Authors
(<https://github.com/rsms/inter>), licensed under the SIL Open Font License,
version 1.1: <https://openfontlicense.org>. The full license text is in the
app under Settings → About → Licenses.

## Sparta Remix Wiki and Logo Editing Wiki

The Sparta remix patterns in the app are from the Sparta Remix Wiki
(<https://spartaremix.fandom.com>), and some effect recipes follow the Logo
Editing Wiki (<https://logo-editing.fandom.com>). Both wikis' text is licensed
under Creative Commons Attribution-ShareAlike (CC BY-SA):
<https://creativecommons.org/licenses/by-sa/3.0/>. The patterns, as used in
SRLE Studio, are shared under the same license.

## Sparta bases

The base catalog and transcriptions (<https://github.com/1ajh/srle-studio>)
are shared under CC BY-SA 4.0. The bases belong to their makers: SRLE Studio
downloads them from where their makers published them and credits them in
the app.

## Flutter and libraries

SRLE Studio is built with Flutter and open-source Dart packages (and, for
video previews, libmpv through media_kit). Their licenses are listed in the
app under Settings → About → Licenses.
