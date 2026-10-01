#!/usr/bin/env python3
"""Builds bases/catalog.json: real Sparta bases the app can download.

Sources (each base keeps its maker's credit and a link to where it lives):
  * Keaton's own site: the official Sparta Extended instrumental base.
  * archive.org base collections (HADES BLACK, Francex, "Some Sparta Bases
    Archive") and single-base uploads.
  * The Sparta Archive FLP Remixes zip on archive.org: bases whose folder
    holds both the FL Studio project and its audio render (FLP_RENDERS), so
    the app reads the base's notes exactly from the project.

Curated transcriptions in bases/transcriptions/<id>.json are linked in.

    python3 tool/build_base_catalog.py
"""
import datetime
import html
import json
import os
import re
import subprocess
import urllib.parse

OUT = 'bases/catalog.json'
TRANSCRIPTIONS = 'bases/transcriptions'
AUDIO = ('.mp3', '.ogg', '.wav', '.flac', '.m4a')
FLP_ZIP_ITEM = 'sparta-archive-flp-remixes'
FLP_ZIP = 'Sparta Archive FLP Remixes.zip'

COLLECTIONS = {
    'hadesblack-spartabases': 'HADES BLACK',
    'francex-sparta-base-collection': None,  # mixed makers; Francex collected them
    'some-sparta-bases-archive': None,
}
# Big multi-artist dumps and remix (not base) uploads to leave out of the search.
SKIP_ITEMS = {'visuals-without-text-and-watermark', 'SpartaRemix.BaseArch', 'basefinal_202412',
              'sparta-base-ultimate-collection', 'DRKRDSpartaRemixesBaseCollections', FLP_ZIP_ITEM}


def get(url):
    return subprocess.check_output(['curl', '-sSL', '-m', '120', url])


def metadata(item):
    return json.loads(get(f'https://archive.org/metadata/{item}'))


def download_url(item, name):
    return f'https://archive.org/download/{item}/' + urllib.parse.quote(name)


def nice_name(filename):
    n = os.path.splitext(os.path.basename(filename))[0]
    n = n.replace('_', ' ').strip()
    n = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', n) if ' ' not in n else n  # SpartaAtlasBase -> Sparta Atlas Base
    return re.sub(r'\s+', ' ', n)


def slug(s):
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')[:80]


def pick_audio(files):
    """One audio file per base: mp3 if there is one, else the smallest other format."""
    by_stem = {}
    for f in files:
        if not f['name'].lower().endswith(AUDIO) or f.get('source') == 'derivative':
            continue
        stem = os.path.splitext(f['name'])[0]
        prev = by_stem.get(stem)
        if prev is None or (f['name'].lower().endswith('.mp3') and not prev['name'].lower().endswith('.mp3')):
            by_stem[stem] = f
    return list(by_stem.values())


def entry(id_, name, maker, url, page, collection, size=None, sha1=None, flp=None, featured=False):
    e = {'id': id_, 'name': name, 'maker': maker or '', 'collection': collection, 'audio': url, 'page': page}
    if size:
        e['size'] = int(size)
    if sha1:
        e['sha1'] = sha1
    if flp:
        e['flp'] = flp
    if featured:
        e['featured'] = True
    return e


def keaton():
    return [entry('keaton/sparta-extended', 'Sparta Extended Remix (official instrumental base)',
                  'Keaton (Funtastic Power!)',
                  'https://keaton-world.com/content/music/2007/'
                  'Funtastic_Power_-_300_This_is_Sparta_EXTENDED_instrumental_base.mp3',
                  'https://keaton-world.com/music.php', "Keaton's World",
                  size=2142545, sha1='457bbe5f433ec2c2e8be8b21cc20256afb6043cf', featured=True)]


def _core(name):
    """A base name without the words every base name has."""
    n = re.sub(r'\(.*?\)|\[.*?\]', ' ', name.lower())
    n = re.sub(r'\b(sparta|base|bases|remix|mix|edition|the|by|and|v\d[\d.]*)\b', ' ', n)
    return re.sub(r'[^a-z0-9]+', ' ', n).strip()


def credits(description):
    """Credited bases from a description listing "- Maker / alias: Base, Base (V1 and V2)":
    a list of (base name core, maker, aliases)."""
    text = re.sub(r'</?(div|p|br|li)[^>]*>', '\n', description or '')
    text = html.unescape(re.sub(r'<[^>]+>', '', text))
    out = []
    for line in text.split('\n'):
        m = re.match(r'^\s*-\s*([^:]+):\s*(.+)$', line)
        if not m:
            continue
        aliases = [a.strip() for a in m.group(1).split('/') if a.strip()]
        names = re.sub(r'\(.*?\)', '', m.group(2))
        for n in re.split(r',|/', names):
            core = _core(n)
            if len(core) >= 3:
                out.append((core, aliases[0], aliases))
    return out


def _flat(s):
    return re.sub(r'[^a-z0-9]', '', s.lower())


def maker_for(name, table):
    """Who made [name]: a credited maker named in it, else the longest
    credited base name inside it (one-word names only when just one maker
    is credited with them)."""
    flat = _flat(name)
    for _, maker, aliases in table:
        for a in aliases:
            fa = _flat(a)
            if len(fa) >= 5 and (fa in flat or re.sub(r'\d+$', '', fa) in flat):
                return maker
    core = ' ' + _core(name) + ' '
    makers_of = {}
    for base, maker, _ in table:
        makers_of.setdefault(base, set()).add(maker)
    best = None
    for base, maker, _ in table:
        if f' {base} ' not in core:
            continue
        if ' ' not in base and len(makers_of[base]) > 1:
            continue
        if best is None or len(base) > len(best[0]):
            best = (base, maker)
    return best[1] if best else None


def collections():
    out = []
    for item, maker in COLLECTIONS.items():
        md = metadata(item)
        title = md.get('metadata', {}).get('title', item)
        table = credits(md.get('metadata', {}).get('description'))
        for f in pick_audio(md.get('files', [])):
            name = nice_name(f['name'])
            if not re.search(r'sparta|base|mix|remix', name, re.I):
                continue
            who = maker or maker_for(name, table)
            out.append(entry(f'{item}/{slug(name)}', name, who, download_url(item, f['name']),
                             f'https://archive.org/details/{item}', title, f.get('size'), f.get('sha1')))
    return out


def single_uploads():
    q = urllib.parse.urlencode({'q': 'title:(sparta) AND title:(base) AND mediatype:audio', 'fl[]': ['identifier'],
                                'rows': 400, 'output': 'json'}, doseq=True)
    docs = json.loads(get('https://archive.org/advancedsearch.php?' + q))['response']['docs']
    out = []
    for d in docs:
        item = d['identifier']
        if item in SKIP_ITEMS or item in COLLECTIONS:
            continue
        md = metadata(item)
        meta = md.get('metadata', {})
        files = pick_audio(md.get('files', []))
        if not files or len(files) > 6:  # big dumps are handled as collections or skipped
            continue
        creator = meta.get('creator')
        if isinstance(creator, list):
            creator = ', '.join(creator)
        for f in files:
            name = meta.get('title') if len(files) == 1 else nice_name(f['name'])
            out.append(entry(f'{item}/{slug(f["name"])}', name, creator, download_url(item, f['name']),
                             f'https://archive.org/details/{item}', 'archive.org upload', f.get('size'), f.get('sha1')))
    return out


# Folders of the FLP archive that hold a render of their project. Most
# folders hold only the project's samples, or another song used as a
# reference (Keaton's Sparta Extended base, a remix, a song the base
# samples), so each pair here was checked by analysis: the render's tempo
# and length match the project's, it lines up on the project's beats, and
# its bass plays the project's bass notes.
FLP_RENDERS = {
    'CJ/Sparta Jolly Rancher Base SCE': 'Copy_Sparta_Jolly_Rancher_Base.mp3',
    'DJCubixTronMusic/Sparta Cubes Mix DJCTME': 'Sparta Cubes Mix V2.mp3',
    'Dalton Stephens/Sparta Hugglebeat Base': 'hb base.mp3',
    'Dalton Stephens/Sparta Keel Base ': 'Sparta Keel BasE.mp3',
    'DangoOlreala/Sparta Dango DOE Base': 'Sparta Dango Mix Remastered_2.mp3',
    'DangoOlreala/Sparta Ognad Base': 'Sparta Ognad Base.mp3',
    'DavidHolandaSpartan/Sparta Overload V2 Base': 'Sparta Overload Base.mp3',
    'DavidHolandaSpartan/Sparta Pure Heartbeat DHSE Base': 'Sparta Pure Heartbeat Remix.mp3',
    'DavidHolandaSpartan/Sparta Victoriya V2 Base': 'Sparta Victoriya Base.wav',
    'Durph/Sparta GYA DFE V2 Base': 'Sparta GYA Base.wav',
    'SiriusJosi/Sparta Kinetic Mix': 'Sparta Kinetic Mix EDT.mp3',
    'enforch/Sparta Announcement Base': 'announcement.mp3',
}


def flp_pairs():
    """FLP archive bases with both a project and a checked render (FLP_RENDERS)."""
    listing = get(f'https://archive.org/download/{FLP_ZIP_ITEM}/{urllib.parse.quote(FLP_ZIP)}/').decode('utf-8', 'replace')
    paths = [urllib.parse.unquote(m) for m in re.findall(r'href="//archive\.org/download/[^"]+\.zip/([^"]+)"', listing)]
    folders = {}
    for p in paths:
        folders.setdefault(os.path.dirname(p), []).append(p)
    out = []
    zip_url = f'https://archive.org/download/{FLP_ZIP_ITEM}/{urllib.parse.quote(FLP_ZIP)}/'
    for folder, render in sorted(FLP_RENDERS.items()):
        files = folders.get(folder, [])
        flps = sorted(f for f in files if f.lower().endswith('.flp'))
        audio = f'{folder}/{render}'
        if not flps or audio not in files:
            print(f'warning: {folder} no longer has its project and render')
            continue
        maker = folder.split('/')[0]
        out.append(entry(f'flp-archive/{slug(folder)}', os.path.basename(folder).strip(), maker,
                         zip_url + urllib.parse.quote(audio), f'https://archive.org/details/{FLP_ZIP_ITEM}',
                         'Sparta Archive FLP Remixes', flp=zip_url + urllib.parse.quote(flps[0])))
    return out


def main():
    bases = keaton() + flp_pairs() + collections() + single_uploads()
    seen, unique = set(), []
    for b in bases:
        key = (slug(b['name']), b.get('size'))
        if key in seen or b['id'] in {u['id'] for u in unique}:
            continue
        seen.add(key)
        unique.append(b)
    for b in unique:
        path = os.path.join(TRANSCRIPTIONS, slug(b['id']) + '.json')
        if os.path.exists(path):
            b['transcription'] = os.path.relpath(path, 'bases')
    unique.sort(key=lambda b: (not b.get('featured'), 'flp' not in b, b['name'].lower()))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w') as f:
        json.dump({'version': 1, 'updated': datetime.date.today().isoformat(), 'bases': unique}, f, indent=1,
                  ensure_ascii=False)
        f.write('\n')
    print(f'{len(unique)} bases written to {OUT}')


if __name__ == '__main__':
    main()
