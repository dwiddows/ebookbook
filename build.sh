#!/usr/bin/env bash

# Originally written by Dominic Widdows, 2021. Updated in 2026 with help from AI agents.

# Builds this book, "LaTeX to eBook", as a PDF and as an epub for Kindle and other
# eReaders. The book is about its own build: its chapters (in chapters/) explain
# each step here and the pitfalls the steps work around.

# Usage: ./build.sh        build PDF, HTML and epub outputs.
#        ./build.sh pdf    build the PDF only.
#        ./build.sh clean  remove outputs.
#
# Everything the build makes goes in the build/ folder, including the finished
# build/ebookbook.pdf and build/ebookbook.epub. The source files stay as they are.

# Assumes that you have programs installed including pdflatex, bibtex, makeindex, make4ht,
# python3, and ebook-convert from Calibre. ImageMagick (magick) is optional:
# with it, the epub gets smaller JPEG copies of the images.

# If you change the name of your main TeX source file, change this variable to the new name.
MAINFILE=ebookbook
AUTHOR="Dominic Widdows" # Of course, you'll want to change this.
TITLE="LaTeX to eBook 2026: The Book About Itself" # And this, to match cover_page.tex.
COVERIMAGE=images/cover.png # The eBook cover: portrait, about 1600 x 2560 pixels.
PDFLATEX="pdflatex -interaction=nonstopmode"
shopt -s nullglob # So images/*.jpg means no files, rather than itself, when there are none.
cd "$(dirname "$0")"
ROOT=$PWD

# Work in build/, and look for the .tex and .bib sources in the folder above.
setup_build() {
    mkdir -p build
    cd build
    export TEXINPUTS=".:$ROOT:"
    export BIBINPUTS=".:$ROOT:"
    # The HTML refers to images/..., and Calibre won't follow a symlink, so copy them.
    mkdir -p images
    cp -p "$ROOT"/images/*.png "$ROOT"/images/*.jpg images/
}

build_pdf() {
    # The first two passes only collect citations and labels, so -draftmode
    # skips writing the PDF (and embedding images) to save time.
    $PDFLATEX -draftmode $MAINFILE > /dev/null
    bibtex $MAINFILE > /dev/null || echo "*** bibtex errors: see build/$MAINFILE.blg ***"
    makeindex -q $MAINFILE
    $PDFLATEX -draftmode $MAINFILE > /dev/null
    makeindex -q $MAINFILE # Again, as the bibliography and index can move pages.
    $PDFLATEX $MAINFILE > /dev/null || echo "*** pdflatex errors: see build/$MAINFILE.log ***"
    n=$(grep -c "Citation .* undefined" "$MAINFILE.log")
    if [[ $n -gt 0 ]]; then echo "*** $n undefined citations in build/$MAINFILE.log ***"; fi
    echo "Wrote build/$MAINFILE.pdf"
}

# PDF only: "./build.sh pdf".
if [[ $# -eq 1 ]] && [[ $1 == "pdf" ]]
   then
       setup_build
       build_pdf

# This is the main build process, from running "./build.sh".
elif [[ $# -eq 0 ]]
   then
       setup_build

       # This makes sure that each image has a corresponding .xbb file to tell make4ht how big to make it.
       # extractbb handles one file per call (given a list, it does only the last).
       for img in images/*.png images/*.jpg; do extractbb -x "$img"; done

       build_pdf

       # HTML with MathML for the equations; lib/ebook-layout.cfg adds CSS for figures and the contents page.
       make4ht -c "$ROOT/lib/ebook-layout.cfg" $MAINFILE.tex "mathjax,mathml,svg" > /dev/null \
           || echo "*** make4ht errors: see build/$MAINFILE.log ***"

       # Fix the HTML for Kindle: inline math, footnote pop-ups, contents page, JPEG images.
       "$ROOT/lib/epub_postprocess.sh" $MAINFILE

       COVER=$COVERIMAGE
       if command -v magick > /dev/null; then
           magick $COVERIMAGE -background white -alpha remove -alpha off -quality 85 -strip epub_images/epub_cover.jpg
           COVER=epub_images/epub_cover.jpg
       fi
       # Chapters are <h2> in make4ht's output; they make the epub's navigation menu.
       ebook-convert $MAINFILE.html $MAINFILE.epub --cover $COVER --title "$TITLE" --authors "$AUTHOR" --language English \
           --use-auto-toc --level1-toc "//h:h2" --level2-toc "" --level3-toc "" \
           --toc-filter "^(References|Bibliography|\[?\d+(\.\d+)*\]?)$" > /dev/null \
           && echo "Wrote build/$MAINFILE.epub"

# This is the build cleanup process, from running "./build.sh clean".
elif [[ $# -eq 1 ]] && [[ $1 == "clean" ]]
    then
       echo "Removing the build folder."
       rm -rf build

else
    echo Arguments not recognized: $@
    echo Usage: ./build.sh to build pdf, html and epub outputs.
    echo ./build.sh pdf to build the pdf only.
    echo ./build.sh clean to remove outputs.
fi
