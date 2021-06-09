#!/usr/bin/env bash

# Usage: ./build.sh to build pdf and html outputs. ./build.sh clean to remove outputs.

MAINFILE=ebookbook

if [[ $# -eq 0 ]]
   then
	pdflatex $MAINFILE
	bibtex $MAINFILE
	pdflatex $MAINFILE
	pdflatex $MAINFILE

	htlatex $MAINFILE.tex
	
elif [[ $# -eq 1 ]] && [[ $1 == "clean" ]]
    then
	for extension in 4ct 4tc aux bbl blg css dvi html idv lg log pdf tmp toc xref; do \
		rm $MAINFILE.$extension; \
	done

else
    echo Arguments not recognized: $@
    echo Usage: ./build.sh to build pdf and html outputs. ./build.sh clean to remove outputs.

fi
