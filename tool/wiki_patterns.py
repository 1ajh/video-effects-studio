#!/usr/bin/env python3
"""Regenerates lib/core/sparta/pattern_data.dart from the Sparta Remix Wiki.

Downloads the wikitext of the pattern pages (spartaremix.fandom.com, CC BY-SA),
pulls every pattern line with its headings, classifies it (pitch / words /
drums and the section it belongs to) and writes the Dart data file.

    python3 tool/wiki_patterns.py
"""
import json
import re
import subprocess
import urllib.parse

PAGES = ["Pitch Patterns", "Pitch Patterns/Custom Pitch Patterns", "Pitch Patterns/Epicness Patterns", "Chorus",
         "DunDunDenDen", "Epicness", "Madness", "Awesomeness", "Freestyles", "Percussion", "Craziness",
         "Epicness (Freestyles)"]
OUT = "lib/core/sparta/pattern_data.dart"
CLASSIC = {
    ('words', 'chorus', 'Standard'), ('words', 'dundundenden', 'DunDunDenDen'), ('words', 'epicness', 'Original'),
    ('words', 'madness', 'Original'), ('pitch', 'intro', 'Original'), ('pitch', 'chorus', 'Original'),
    ('pitch', 'dundundenden', 'Original'), ('pitch', 'epicness', 'Original'), ('pitch', 'madness', 'First Pattern'),
    ('pitch', 'madness', 'Second Pattern (aka Trance Gate)'), ('pitch', 'awesomeness', 'Awesomeness 1 (Major)'),
    ('pitch', 'awesomeness', 'Awesomeness 2 (Major)'), ('pitch', 'awesomeness', 'Awesomeness 1 (Minor)'),
    ('pitch', 'awesomeness', 'Awesomeness 2 (Minor)'), ('drums', 'percussion', 'Normal Percussion'),
}
GENERIC = {'Pitch Patterns List', 'List', 'Patterns', 'Other Patterns', 'Pattern', 'Original Patterns',
           'Custom Patterns', 'Chorus Patterns', 'Freestyles', 'The Epicness Freestyles', 'Pitches', 'Symbols:',
           'Symbol key', 'Epicness Pattern', 'Original Pattern'}


def wikitext(title):
    url = 'https://spartaremix.fandom.com/api.php?' + urllib.parse.urlencode(
        {'action': 'parse', 'page': title, 'prop': 'wikitext', 'format': 'json'})
    # The site rejects urllib's user agent; curl works.
    return json.loads(subprocess.check_output(['curl', '-sS', '-m', '60', url]))['parse']['wikitext']['*']


def raw_lines():
    out = []
    for page in PAGES:
        h = [''] * 8
        for line in wikitext(page).split('\n'):
            m = re.match(r'^(=+)\s*(.*?)\s*\1\s*$', line)
            if m:
                lvl = min(len(m.group(1)), 7)
                h[lvl - 1] = re.sub(r"'''|\[\[[^|\]]*\||\]\]|\[\[|\[http\S+\s|\]", "", m.group(2)).strip()
                for k in range(lvl, 8):
                    h[k] = ''
                continue
            if line.startswith(' ') and line.strip() and not line.strip().startswith(('FSC', 'http')) \
                    and re.search(r'\d', line):
                out.append({'page': page, 'h': [x for x in h if x], 'text': line.strip()})
    return out


def clean(t):
    t = t.replace('﻿', '').replace('<code>', '').replace('</code>', '').replace('М', '').strip()
    t = re.sub(r"^(The first pattern|The other pattern|First one since \([\d.]+\)|First one \(the famous one\)|"
               r"Second one since \([\d.]+\)|Second one|First one|Third one sine \([\d.]+\)|\d\.)\s*:?\s*", '', t)
    t = re.sub(r"\s*\((NOTE THE REST AFTER THE 2nd HALF|Note: Pitch Shift[^)]*|B is both[^)]*)\)", '', t)
    t = re.sub(r"\s*'''\(Repeat\)'''", '', t)
    return re.sub(r"\s+or\s*$", '', t).strip()


def kind_for(page, h):
    hs = ' > '.join(h).lower()
    if page == 'Percussion':
        return 'drums'
    if page == 'Madness':
        return 'pitch' if 'pitch patterns' in hs else 'words'
    if page in ('Chorus', 'DunDunDenDen', 'Epicness', 'Freestyles', 'Epicness (Freestyles)'):
        return 'words'
    return 'pitch'


def valid(kind, t):
    if kind == 'pitch':
        return re.fullmatch(r"[-+\d*'\"_/\\ ,|]+", t) is not None
    return re.fullmatch(r"[\dAB*'#_/\\ ]+", t) is not None


def section(page, kind, h, name):
    s, n = ' > '.join(h).lower(), name.lower()
    if kind == 'drums':
        return 'percussion'
    fixed = {'Pitch Patterns/Epicness Patterns': 'epicness', 'Awesomeness': 'awesomeness', 'Craziness': 'craziness',
             'Madness': 'madness', 'Chorus': 'chorus', 'Freestyles': 'chorus', 'DunDunDenDen': 'dundundenden'}
    if page in fixed:
        return fixed[page]
    if page.startswith('Epicness'):
        return 'epicness'
    if page == 'Pitch Patterns':
        for k, sec in [('awesomeness', 'awesomeness'), ('intro', 'intro'), ('chorus pattern', 'chorus'),
                       ('progression twist', 'twist'), ('chords', 'chords'), ('dundundenden', 'dundundenden'),
                       ('execution', 'execution'), ('madness', 'madness')]:
            if k in s:
                return sec
        return 'custom'
    if 'pre-epicness' in n or 'pre epicnes' in n:
        return 'preEpicness'
    if 'post-epicness' in n:
        return 'postEpicness'
    if 'awesomeness' in n:
        return 'awesomeness'
    if '(epicness)' in n:
        return 'epicness'
    return 'custom'


def curate(raw):
    groups, order = {}, []
    for r in raw:
        page = r['page']
        kind = kind_for(page, r['h'])
        text = clean(r['text'])
        if not text or not valid(kind, text):
            continue
        h = r['h'][-1:] if page.endswith('Custom Pitch Patterns') else r['h']  # its heading levels are inconsistent
        key = (page, kind, tuple(h))
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(text)
    out, seen = [], set()

    def add(kind, sec, name, parent, page, lines, layered):
        if (kind, tuple(lines)) in seen:
            return
        seen.add((kind, tuple(lines)))
        out.append(dict(kind=kind, section=sec, name=name.replace("''", ''), parent=parent, page=page,
                        lines=lines, layered=layered))

    for page, kind, h in order:
        lines = groups[(page, kind, h)]
        hh = [x for x in h if x not in GENERIC]
        name = hh[-1] if hh else {'Chorus': 'Standard', 'Madness': 'Original',
                                  'Epicness (Freestyles)': 'Epicness freestyle'}.get(page, page)
        parent, sec = ' > '.join(hh[:-1]), section(page, kind, list(h), name)
        if kind == 'drums' or (kind == 'pitch' and ('chords' in ' '.join(h).lower() or name == 'Metro/Minor')):
            add(kind, sec, name, parent, page, lines, True)
            continue
        if kind == 'words':
            layers = []
            for line in lines:
                if layers and set(line[:8]) <= set('_'):
                    layers[-1].append(line)
                else:
                    layers.append([line])
            for i, g in enumerate(layers):
                add(kind, sec, name if len(layers) == 1 else f'{name} {i + 1}', parent, page, g, len(g) > 1)
            continue
        for i, line in enumerate(lines):
            add(kind, sec, name if len(lines) == 1 else f'{name} {i + 1}', parent, page, [line], False)
    for o in out:
        n = o['name']
        if o['page'] == 'Chorus':
            o['name'] = {'Standard 1': 'Standard', 'Standard 2': 'Standard (2 then 1 feel)',
                         'Standard 3': 'Standard with 32nds'}.get(n, n)
        if o['page'] == 'Madness' and o['kind'] == 'pitch':
            o['name'] = {'Pitch Patterns 2': 'Original (second half)', 'Pitch Patterns 3': 'Version'}.get(n, n)
        if n.startswith('Michael6/narayan23456'):
            idx = int(n.rsplit(' ', 1)[1])
            o['name'] = 'Michael6/narayan23456 ' + ['Original', 'Pre-Epicness', 'Venom', 'Pre-Ending'][idx - 1]
            o['section'] = 'preEpicness' if idx == 2 else 'custom'
        if n == 'ORIGINAL':
            o['name'] = 'Original'
        if n == 'Francium pre epicnes':
            o['name'] = 'Francium Pre-Epicness'
        if n.startswith('Others either accidentally'):
            o['name'] = 'Transposed 1 and 2 ' + n.rsplit(' ', 1)[1]
        if n.startswith('KingSpartaX37 (Corrected'):
            o['name'] = 'KingSpartaX37 (corrected by TehColombianSpartan)'
    return out


def dart_string(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


def write(out):
    lines = ["// GENERATED from the Sparta Remix Wiki (spartaremix.fandom.com), CC BY-SA.",
             "// Pattern pages: Pitch Patterns (+ Custom / Epicness Patterns), Chorus, DunDunDenDen,",
             "// Epicness (+ Freestyles), Madness, Awesomeness, Freestyles, Percussion, Craziness.",
             "// Regenerate with tool/wiki_patterns.py; edit by hand only to fix a pattern.", "",
             "part of 'patterns.dart';", "", "const _wikiPatterns = <_WikiPattern>["]
    for o in out:
        extra = (f", group: {dart_string(o['parent'])}" if o['parent'] else '') + \
                (", layered: true" if o['layered'] else '') + \
                (", classic: true" if (o['kind'], o['section'], o['name']) in CLASSIC else '')
        lines.append(f"  _WikiPattern(PatternKind.{o['kind']}, {dart_string(o['section'])}, {dart_string(o['name'])}, "
                     f"{dart_string(o['page'])}, [{', '.join(dart_string(x) for x in o['lines'])}]{extra}),")
    lines.append("];")
    with open(OUT, 'w') as f:
        f.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    patterns = curate(raw_lines())
    write(patterns)
    print(f'{len(patterns)} patterns written to {OUT}')
