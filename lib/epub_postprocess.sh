#!/usr/bin/env bash

# Usage: lib/epub_postprocess.sh MAINFILE   (run in the folder holding MAINFILE.html)
#
# Fixes make4ht's HTML for Kindle before ebook-convert turns it into an epub.
# The PDF is never touched. Called by build.sh and tests/build_diagnostic.sh.
#
# These fixes go into the HTML itself because ebook-convert drops CSS rules
# that target MathML elements.

MAIN=$1
LIB="$(cd "$(dirname "$0")" && pwd)"

# Simple inline math becomes plain HTML (italics, <sub>, <sup>): Kindle sets any
# inline MathML in a small math font with a raised baseline. Also removes the
# stray rules Kindle draws in matrices, and makes \big brackets stretchy.
# tex4ht writes footnote text to separate numbered files, so those get the
# same treatment.
for html in "$MAIN.html" "$MAIN"[0-9]*.html; do
    [[ -f "$html" ]] && python3 "$LIB/epub_inline_math.py" "$html"
done

# Footnotes: link each note back to its marker, so Kindle shows a pop-up
# instead of jumping to the end of the book.
python3 "$LIB/epub_footnotes.py" "$MAIN.html"

# Contents page as one compact paragraph per entry (Kindle draws tex4ht's
# line breaks there as blank lines).
python3 "$LIB/epub_toc.py" "$MAIN.html"

# Kindle re-encodes every PNG as a large JPEG but passes JPEGs through
# unchanged, and Amazon charges a delivery fee per MB. So the epub gets JPEG
# copies sized for Kindle screens, while the PDF keeps the lossless PNGs.
# Copies are cached in epub_images/ and only redone when the PNG changes.
if command -v magick > /dev/null; then
    mkdir -p epub_images
    for png in $(grep -o "src='images/[^']*\.png'" "$MAIN.html" | sed "s/src='images\///; s/'$//" | sort -u); do
        jpg="epub_images/${png%.png}.jpg"
        mkdir -p "$(dirname "$jpg")"
        if [[ ! -f "$jpg" || "images/$png" -nt "$jpg" ]]; then
            magick "images/$png" -background white -alpha remove -alpha off \
                -resize '1264x1680>' -quality 80 -strip "$jpg"
        fi
    done
    perl -pi -e "s{src='images/([^']*)\.png'}{src='epub_images/\$1.jpg'}g" "$MAIN.html"
else
    echo "epub_postprocess: ImageMagick (magick) not found; epub keeps the PNG images"
fi
