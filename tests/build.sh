#!/usr/bin/env bash

# Usage: ./build.sh TESTFILE.tex

# First argument is the file with the test example.
if [[ $# -ne 1 ]]
then
   echo Usage: ./build.sh TESTFILE
   exit 1
fi
     
TESTFILE="$(basename $1 .tex)"

mkdir -p output
cd output
pdflatex ../$TESTFILE.tex
make4ht ../$TESTFILE.tex
ebook-convert $TESTFILE.html $TESTFILE.epub
cd ..
