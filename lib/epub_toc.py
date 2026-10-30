#!/usr/bin/env python3
"""Rebuild the book's contents page as one compact paragraph per entry, for the epub.

tex4ht writes the contents as spans separated by <br />, and Calibre gives those
<br /> elements display:block, which Kindle draws as extra blank lines, so the
contents come out widely spaced. Here each entry becomes its own paragraph with
no margins: chapters bold, sections indented. The PDF is unaffected.

Usage: python3 epub_toc.py main.html
"""
import re
import sys

TOC = re.compile(r"(<div class='tableofcontents'>)(.*?)(</div>)", re.S)
ENTRY = re.compile(r"<span class='(\w+)'>(.*?)</span>", re.S)
STYLE = {
    'sectionToc': 'margin:0 0 0 1.5em; text-indent:0;',
}
CHAPTER_STYLE = 'margin:0.4em 0 0 0; text-indent:0; font-weight:bold;'


def rebuild(match):
    entries = ENTRY.findall(match.group(2))
    paras = [f"<p class='toc-{kind}' style='{STYLE.get(kind, CHAPTER_STYLE)}'>{text.strip()}</p>"
             for kind, text in entries]
    return match.group(1) + '\n'.join(paras) + match.group(3)


if __name__ == '__main__':
    path = sys.argv[1]
    with open(path, encoding='utf-8') as f:
        html = f.read()
    # Only the real contents page (it has chapter entries); tex4ht reuses the
    # class for other boxes.
    html, n = TOC.subn(lambda m: rebuild(m) if 'chapterToc' in m.group(2) else m.group(0), html, count=1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(html)
    entries = html.count("class='toc-")
    print(f'epub_toc: contents page rebuilt as {entries} compact entries')
