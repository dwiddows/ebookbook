#!/usr/bin/env python3
r"""Turn simple inline MathML in the make4ht HTML into plain HTML, for the epub.

Kindle typesets every inline <math> element in its own math font, smaller and
with a raised baseline. Simple inline math (letters, numbers, operators,
subscripts, superscripts, bold, fractions, square roots) reads better as
ordinary italic text with <sub>/<sup>; fractions use a slash (dy/dx) and roots
the radical sign, bracketed where needed; script capitals (\mathcal{L}) become
the Unicode letters such as U+2112. Anything else (accents, tables) is left as
MathML. Display math and the PDF are never touched,
except that every MathML table (matrix) gets explicit rowlines/columnlines/frame
"none": tex4ht writes rowlines='', which Kindle draws as rules between rows;
\big( / \bigg( brackets become stretchy fences, like \left( \right); and
equation link targets move out of the MathML, where Kindle can't reach them.

Usage (called from epub_postprocess.sh): python3 epub_inline_math.py main.html
"""
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET

NS = '{http://www.w3.org/1998/Math/MathML}'
INLINE_MATH = re.compile(r"<math display='inline'[^>]*>.*?</math>", re.S)
SPACED_CLASSES = ('MathClass-bin', 'MathClass-rel')
NBSP = ' '


class Unsupported(Exception):
    pass


def plain(text):
    """Map math-alphanumeric characters (e.g. U+1D456 italic i) to ordinary ones."""
    return ''.join(unicodedata.normalize('NFKC', c) if 0x1D400 <= ord(c) <= 0x1D7FF else c
                   for c in text)


def is_bold(text):
    return any('BOLD' in unicodedata.name(c, '') for c in text)


def esc(text):
    return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


# Script capitals: the letterlike symbols where Unicode has them (wider font
# support), otherwise the mathematical script block.
SCRIPT_LETTERLIKE = {'B': '\u212c', 'E': '\u2130', 'F': '\u2131', 'H': '\u210b',
                     'I': '\u2110', 'L': '\u2112', 'M': '\u2133', 'R': '\u211b'}


def script(text):
    return ''.join(SCRIPT_LETTERLIKE.get(c) or (chr(0x1D49C + ord(c) - ord('A')) if 'A' <= c <= 'Z'
                                                 else c) for c in text)


def style(text, variant):
    if variant == 'script':
        return esc(script(text))
    t = esc(text)
    if variant == 'italic':
        return f'<i>{t}</i>'
    if variant == 'bold':
        return f'<b>{t}</b>'
    if variant == 'bold-italic':
        return f'<b><i>{t}</i></b>'
    if variant == 'normal':
        return t
    raise Unsupported(variant)


def is_operand_end(el):
    """True if el can stand before a binary operator (so a following minus is binary)."""
    if el.tag.replace(NS, '') != 'mo':
        return True
    return 'MathClass-close' in el.get('class', '')


def has_operator(el):
    """True if el (or its top-level mrow) contains a binary or relation operator."""
    kids = list(el) if el.tag.replace(NS, '') in ('mrow', 'mstyle') else [el]
    if len(kids) == 1 and kids[0] is not el and kids[0].tag.replace(NS, '') in ('mrow', 'mstyle'):
        return has_operator(kids[0])
    return any(k.tag.replace(NS, '') == 'mo' and
               any(c in k.get('class', '') for c in SPACED_CLASSES) for k in kids)


def bracket(el, variant):
    """Convert el, in brackets if it has more than one term."""
    html = convert(el, variant)
    return f'({html})' if has_operator(el) else html


def convert_seq(kids, variant):
    """Convert siblings in order; a minus with no operand before it is unary (unspaced),
    and a fraction followed directly by an operand is bracketed: (1/3)u."""
    out, prev = [], None
    kids = [k for k in kids]
    for i, k in enumerate(kids):
        unary = k.tag.replace(NS, '') == 'mo' and (prev is None or not is_operand_end(prev))
        html = convert(k, variant, unary)
        if k.tag.replace(NS, '') == 'mfrac' and i + 1 < len(kids) and is_operand_end(kids[i + 1]) \
                and kids[i + 1].tag.replace(NS, '') != 'mo':
            html = f'({html})'
        out.append(html)
        if (k.text or '').strip().replace('\u2061', '') or len(k):
            prev = k
    return ''.join(out)


def convert(el, variant=None, unary=False):
    tag = el.tag.replace(NS, '')
    kids = list(el)
    text = (el.text or '').strip()
    if tag in ('mrow', 'mstyle'):
        v = el.get('mathvariant', variant)
        if v not in (None, 'normal', 'italic', 'bold', 'bold-italic', 'script'):
            raise Unsupported(v)
        return convert_seq(kids, v)
    if tag == 'mi':
        if kids:
            raise Unsupported('mi children')
        v = el.get('mathvariant') or variant
        if v is None:
            p = plain(text)
            if is_bold(text):
                v = 'bold'
            elif len(p) == 1 and unicodedata.category(p).startswith('L'):
                v = 'italic'
            else:
                v = 'normal'  # function names (cos, log) and symbols such as the sum sign
        return style(plain(text), v)
    if tag == 'mn':
        return esc(plain(text))
    if tag == 'mtext':
        return esc(text)
    if tag == 'mspace':
        return ' '
    if tag == 'mo':
        t = text.replace('\u2061', '')  # invisible function application
        if not t:
            return ''
        if unary or t in ('/', '\u2215'):  # unary minus; a slash written in the source
            return esc(t)
        if any(c in el.get('class', '') for c in SPACED_CLASSES):
            return f'{NBSP}{esc(t)} '
        if 'MathClass-punc' in el.get('class', ''):
            return esc(t) + ' '
        return esc(t)
    if tag == 'msub' and len(kids) == 2:
        return f'{convert(kids[0], variant)}<sub>{convert(kids[1], variant)}</sub>'
    if tag == 'msup' and len(kids) == 2:
        return f'{convert(kids[0], variant)}<sup>{convert(kids[1], variant)}</sup>'
    if tag == 'msubsup' and len(kids) == 3:
        return (f'{convert(kids[0], variant)}<sub>{convert(kids[1], variant)}</sub>'
                f'<sup>{convert(kids[2], variant)}</sup>')
    if tag == 'mfrac' and len(kids) == 2 and el.get('linethickness') in (None, '1'):
        return f'{bracket(kids[0], variant)}/{bracket(kids[1], variant)}'
    if tag == 'msqrt':
        inner = kids[0] if len(kids) == 1 else el
        html = convert_seq(kids, variant)
        return f'\u221a({html})' if (len(kids) > 1 and has_operator(el)) or \
            (len(kids) == 1 and has_operator(inner)) else f'\u221a{html}'
    raise Unsupported(tag)


def replace(match):
    src = match.group(0)
    try:
        root = ET.fromstring(src)
        html = convert_seq(list(root), None).strip()
    except (Unsupported, ET.ParseError):
        replace.kept += 1
        return src
    replace.done += 1
    return f'<span class="inlinemath">{html}</span>'


replace.done = replace.kept = 0

# \big( \Big( \bigg( ... come out as a bracket character scaled with mathsize,
# which sits on the baseline instead of centring on what it encloses. Make them
# stretchy fences instead, like \left( ... \right).
SIZED_FENCE = re.compile(r"<mo([^>]*?)\smathsize='[^']*'([^>]*)>")


def stretchy(match):
    attrs = (match.group(1) + match.group(2)).replace(" stretchy='false'", '')
    return f"<mo{attrs} stretchy='true' symmetric='true'>"


# Equation labels: tex4ht puts the link target for \ref on an <mstyle> inside
# the MathML, and Kindle can't follow a link there. Move each target to an
# empty anchor just before the <math> element.
BLOCK_MATH = re.compile(r"<math\b[^>]*display='block'.*?</math>", re.S)
LABEL = re.compile(r"<mstyle class='label' id='([^']+)'></mstyle>")


def anchor_labels(match):
    ids = LABEL.findall(match.group(0))
    anchor_labels.moved += len(ids)
    return ''.join(f"<a id='{i}'></a>" for i in ids) + LABEL.sub('', match.group(0))


anchor_labels.moved = 0

MTABLE = re.compile(r"<mtable\b([^>]*)>")
LINE_ATTRS = re.compile(r"""\s(?:rowlines|columnlines|frame|class|style)=(?:'[^']*'|"[^"]*")""")


def no_rules(match):
    attrs = LINE_ATTRS.sub('', match.group(1))
    return f"<mtable{attrs} rowlines='none' columnlines='none' frame='none'>"


if __name__ == '__main__':
    path = sys.argv[1]
    with open(path, encoding='utf-8') as f:
        html = f.read()
    html = INLINE_MATH.sub(replace, html)
    html, tables = MTABLE.subn(no_rules, html)
    html, fences = SIZED_FENCE.subn(stretchy, html)
    html = BLOCK_MATH.sub(anchor_labels, html)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f'epub_inline_math: {replace.done} inline formulas converted to HTML, '
          f'{replace.kept} left as MathML; {tables} matrices set to no rules; '
          f'{fences} big brackets made stretchy; {anchor_labels.moved} equation link targets moved out of MathML')
