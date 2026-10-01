# Sparta base catalog

`catalog.json` lists real Sparta bases the app can download, each credited to
its maker and linked to where it's published (Keaton's site, archive.org
collections and uploads, and the Sparta Archive FLP Remixes, whose bases come
with their FL Studio projects). It's built by `tool/build_base_catalog.py` and
bundled with the app; the app also fetches the newest copy from this folder,
so additions reach everyone without an app update.

`transcriptions/` holds checked transcriptions (the base's sections, hit notes
and drums) sent in by people through the **Base transcription** issue form.
When a maintainer labels such an issue `transcription-approved`, the
`Add approved transcription` workflow checks the attached file and opens a
pull request adding it here with the sender's credit.

Maintainers can make a transcription from a base's project (exact) or audio
(a draft to check) with
`dart run tool/transcribe_base.dart <base.flp|.mid|.mp3> [--audio base.mp3] --name … --maker … --catalog <id> --credit …`.
