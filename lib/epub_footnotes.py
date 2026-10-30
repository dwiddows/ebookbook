#!/usr/bin/env python3
"""Give tex4ht footnotes a link back to their marker, for Kindle pop-up notes.

tex4ht puts footnote text in a separate HTML file and links the marker in the
text to it, but not back. Kindle shows a footnote as a pop-up only when the
marker and the note link to each other (Kindle Publishing Guidelines 11.3.12),
otherwise tapping the marker jumps to the end of the book. This adds an id to
each marker and turns the note's number into a link back to it.

Usage: python3 epub_footnotes.py main.html
"""
import os
import re
import sys

MARKER = re.compile(r"<a href='([^'#]+)#(fn\d+x\d+)'>")


def main(path):
    folder, main_name = os.path.split(path)
    with open(path, encoding='utf-8') as f:
        html = f.read()
    notes = {}  # footnote file -> ids

    def add_id(m):
        notes.setdefault(m.group(1), set()).add(m.group(2))
        return f"<a href='{m.group(1)}#{m.group(2)}' id='{m.group(2)}-ref'>"

    html = MARKER.sub(add_id, html)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(html)

    linked = 0
    for name, ids in notes.items():
        fpath = os.path.join(folder, name)
        with open(fpath, encoding='utf-8') as f:
            fn = f.read()
        for i in ids:
            fn, n = re.subn(rf"<a id='{i}'>", f"<a id='{i}' href='{main_name}#{i}-ref'>", fn)
            linked += n
        with open(fpath, 'w', encoding='utf-8') as f:
            f.write(fn)
    print(f'epub_footnotes: {linked} footnotes linked back to their markers')


if __name__ == '__main__':
    main(sys.argv[1])
