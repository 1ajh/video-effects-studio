#!/usr/bin/env python3
"""Adds a transcription sent in through the "Base transcription" issue form.

Reads the issue body (BODY), downloads the attached .sparta.json, checks it,
stores it in bases/transcriptions/ and links it from bases/catalog.json.
Run by .github/workflows/transcription-pr.yml.
"""
import json
import os
import re
import subprocess
import sys


def field(body, label):
    m = re.search(r'###\s*' + re.escape(label) + r'\s*\n+(.*?)(?=\n###|\Z)', body, re.S)
    value = m.group(1).strip() if m else ''
    return '' if value == '_No response_' else value


def slug(s):
    return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')[:80]


def main():
    body = os.environ['BODY']
    text = field(body, 'Transcription file')
    urls = re.findall(r'https://github\.com/user-attachments/files/\S+?\.json|https://github\.com/[^\s)]+/files/\d+/[^\s)]+\.json', text)
    if urls:
        raw = subprocess.check_output(['curl', '-sSL', '-m', '60', urls[0]]).decode('utf-8')
    else:
        m = re.search(r'```(?:json)?\s*(\{.*\})\s*```', text, re.S)
        raw = m.group(1) if m else text
    data = json.loads(raw)
    if data.get('format') != 'sparta-base-transcription':
        sys.exit('Not a Sparta base transcription.')
    for key in ('bpm', 'root', 'lengthBeats', 'sections', 'hits'):
        if key not in data:
            sys.exit(f'Missing "{key}".')
    credit = field(body, 'Credit') or os.environ.get('AUTHOR', '')
    data['credit'] = credit
    data['source'] = 'curated'
    base = data.setdefault('base', {})
    catalog_id = field(body, 'Catalog id') or base.get('catalogId', '')
    sha1 = field(body, 'Audio SHA-1') or base.get('audioSha1', '')
    name = field(body, 'Base') or base.get('name', 'base')
    base.update({k: v for k, v in {'name': name, 'catalogId': catalog_id, 'audioSha1': sha1}.items() if v})

    catalog_path = 'bases/catalog.json'
    catalog = json.load(open(catalog_path))
    entry = next((b for b in catalog['bases'] if catalog_id and b['id'] == catalog_id), None) or \
        next((b for b in catalog['bases'] if sha1 and b.get('sha1') == sha1), None)
    file_id = slug(entry['id'] if entry else (sha1 or name))
    path = f'bases/transcriptions/{file_id}.json'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write('\n')
    if entry:
        entry['transcription'] = os.path.relpath(path, 'bases')
        with open(catalog_path, 'w') as f:
            json.dump(catalog, f, indent=1, ensure_ascii=False)
            f.write('\n')
    with open(os.environ.get('GITHUB_OUTPUT', '/dev/null'), 'a') as out:
        out.write(f'name={name}\ncredit={credit}\n')
    print(f'Added {path}' + (f' for catalog base {entry["id"]}' if entry else ' (no catalog match: matched by audio hash)'))


if __name__ == '__main__':
    main()
