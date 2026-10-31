#!/usr/bin/env bash

# Usage: tests/build_diagnostic.sh
#
# Builds the Kindle diagnostic book (tests/kindle_diagnostic.tex) as two epubs
# from one make4ht run, to send to a Kindle and compare test by test:
#   kindle_diagnostic-raw.epub  make4ht output as it is
#   kindle_diagnostic.epub      after lib/epub_postprocess.sh, as in build.sh
# plus kindle_diagnostic.pdf, all in build/kindle_diagnostic/ (with the build's
# other files).
# Don't run it while ./build.sh is running: make4ht runs that overlap can
# collide on tex4ht's temporary files and hang.

DIAGFILE=kindle_diagnostic
AUTHOR="LaTeX to eBook"
# Amazon's Kindle Previewer command-line converter, if installed. Its log reports
# problems in the Kindle conversion (such as unresolved links) that Calibre doesn't.
KPCLI="$HOME/Applications/Kindle Previewer 4.app/Contents/MacOS/KindlePreviewer4CLI"
[[ -x $KPCLI ]] || KPCLI="/Applications/Kindle Previewer 4.app/Contents/MacOS/KindlePreviewer4CLI"

cd "$(dirname "$0")"
TESTS=$PWD
ROOT=$(cd .. && pwd)
BUILD=build/$DIAGFILE
mkdir -p "$ROOT/$BUILD"
cd "$ROOT/$BUILD"
rm -rf raw images epub_images
# Copy the images the diagnostic uses (Calibre won't follow a symlink).
mkdir images
cp "$ROOT/images/sea_countries.png" images/
for img in images/*.png; do extractbb -x "$img"; done
cp "$TESTS/$DIAGFILE.tex" .

STAMP="$(date '+%Y-%m-%d %H:%M'), commit $(git -C "$ROOT" rev-parse --short HEAD)"
git -C "$ROOT" diff --quiet HEAD || STAMP="$STAMP plus uncommitted changes"
echo "\\def\\kstamp{$STAMP}" > ${DIAGFILE}_stamp.tex

# Find lib/packages.tex and lib/commands.tex in the repository root.
export TEXINPUTS=".:$ROOT:"

pdflatex -interaction=nonstopmode $DIAGFILE > /dev/null
pdflatex -interaction=nonstopmode $DIAGFILE > /dev/null || echo "*** pdflatex errors: see $BUILD/$DIAGFILE.log ***"
make4ht -c "$ROOT/lib/ebook-layout.cfg" $DIAGFILE.tex "mathjax,mathml,svg" > make4ht.log 2>&1 \
    || echo "*** make4ht errors: see $BUILD/make4ht.log ***"

# Keep a copy of the unprocessed HTML, then post-process as build.sh does.
mkdir raw
cp $DIAGFILE*.html $DIAGFILE*.css raw/
cp -R images raw/
"$ROOT/lib/epub_postprocess.sh" $DIAGFILE

# Its own grey cover, so it can't be mistaken for a book.
COVERTIME=$(date '+%Y-%m-%d %H:%M')
cover() {  # cover FILE LABEL
    magick -size 1600x2400 xc:'#e8e8e8' -fill '#202020' -font Helvetica-Bold -gravity North \
        -pointsize 150 -annotate +0+620 "Kindle" -annotate +0+800 "Diagnostic" \
        -font Helvetica -pointsize 120 -annotate +0+1150 "$2" \
        -pointsize 64 -annotate +0+1360 "$COVERTIME" -quality 85 "$1"
}
convert_epub() {  # convert_epub HTML EPUB COVER LABEL
    ebook-convert "$1" "$2" ${3:+--cover "$3"} --authors "$AUTHOR" --language English \
        --title "Kindle Diagnostic, $4 ($COVERTIME)" \
        --use-auto-toc --level1-toc "//h:h2" --level2-toc "" --level3-toc "" > ebook-convert.log 2>&1 \
        || echo "*** ebook-convert errors: see $BUILD/ebook-convert.log ***"
}
if command -v magick > /dev/null; then
    cover epub_images/cover_fixed.jpg "fixed"
    cover raw/cover_raw.jpg "raw"
    convert_epub $DIAGFILE.html $DIAGFILE.epub epub_images/cover_fixed.jpg "fixed"
    (cd raw && convert_epub $DIAGFILE.html $DIAGFILE-raw.epub cover_raw.jpg "raw")
else
    convert_epub $DIAGFILE.html $DIAGFILE.epub "" "fixed"
    (cd raw && convert_epub $DIAGFILE.html $DIAGFILE-raw.epub "" "raw")
fi
mv raw/$DIAGFILE-raw.epub .

if [[ -x $KPCLI ]]; then
    rm -rf kp && mkdir kp
    "$KPCLI" "$PWD/$DIAGFILE.epub" --convert --output "$PWD/kp" > /dev/null
    echo "Kindle Previewer conversion log (fixed version):"
    tail -n +4 kp/Logs/*.csv | cut -d, -f1-2 | sed 's#/[^ ]*/mobi-[^/]*/##'
fi
echo "Built $BUILD/$DIAGFILE.epub and $BUILD/$DIAGFILE-raw.epub ($STAMP)."
