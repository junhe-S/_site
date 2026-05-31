#!/usr/bin/env python3
"""
Build system for Jun He's blog.
Converts Markdown posts to HTML with executable Python/R code blocks.

Usage:
    python build.py              # Build all posts
    python build.py --watch      # Build all, then watch for changes
    python build.py --post slug  # Build a single post
    python build.py --no-exec    # Build without executing code blocks
"""

import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import datetime as _dt
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path

import markdown
import yaml
from jinja2 import Environment, FileSystemLoader

ROOT = Path(__file__).parent
POSTS_DIR = ROOT / "posts"
TEMPLATES_DIR = ROOT / "templates"

# All content sections that contain buildable markdown pages
SECTIONS = ["posts", "research", "note", "data", "bergen"]

env = Environment(loader=FileSystemLoader(str(TEMPLATES_DIR)))


# ---------------------------------------------------------------------------
# Journals (for grouping the Research listing by venue)
# ---------------------------------------------------------------------------

# abbreviation -> (full name, sort rank). Lower rank sorts first; working papers
# (SSRN) sort last. Unknown journals fall between known journals and SSRN.
JOURNAL_INFO = {
    "JF":   ("Journal of Finance", 1),
    "JFE":  ("Journal of Financial Economics", 2),
    "RFS":  ("Review of Financial Studies", 3),
    "JFQA": ("Journal of Financial and Quantitative Analysis", 4),
    "RFin": ("Review of Finance", 5),
    "JFI":  ("Journal of Financial Intermediation", 6),
    "MS":   ("Management Science", 7),
    "JPE":  ("Journal of Political Economy", 8),
    "QJE":  ("Quarterly Journal of Economics", 9),
    "AER":  ("American Economic Review", 10),
    "RES":  ("Review of Economic Studies", 11),
    "NBER": ("NBER Working Paper", 998),
    "SSRN": ("Working Papers", 999),
}


def _author_slug(name):
    """URL slug for an author page, e.g. "John H. Cochrane" -> "john-h-cochrane"."""
    s = (name or "").strip().lower().replace(".", "")
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def author_links(paper_authors):
    """Split a "First Last, First Last" string into [{name, url}] for templates."""
    out = []
    for n in [a.strip() for a in (paper_authors or "").split(",") if a.strip()]:
        out.append({"name": n, "url": f"/research/author/{_author_slug(n)}/"})
    return out


def parse_venue(venue):
    """Split a `venue` string like "2026 JFE" into (article_year, journal info).

    Returns a dict with: art_year (int), journal (abbr), journal_full,
    journal_label ("Full Name (ABBR)"), journal_rank.
    """
    venue = (venue or "").strip()
    m = re.search(r"\b(\d{4})\b", venue)
    art_year = int(m.group(1)) if m else 0
    # capture the month if the date token is "YYYY/MM"
    mm = re.search(r"\b\d{4}/(\d{1,2})\b", venue)
    art_month = int(mm.group(1)) if mm else 0
    # journal = everything that isn't the date token (YYYY or YYYY/MM)
    abbr = re.sub(r"\b\d{4}(?:/\d{1,2})?\b", "", venue).strip() or "Other"
    full, rank = JOURNAL_INFO.get(abbr, (abbr, 500))
    label = f"{full} ({abbr})" if full != abbr else abbr
    # display tag for the listing: date only (the journal is the group header).
    date_tag = ""
    if art_year:
        date_tag = f"{art_year}/{art_month:02d}" if art_month else f"{art_year}"
    return {
        "art_year": art_year,
        "art_month": art_month,
        "date_tag": date_tag,
        "journal": abbr,
        "journal_full": full,
        "journal_label": label,
        "journal_rank": rank,
        "journal_slug": re.sub(r"[^a-z0-9]+", "-", abbr.lower()).strip("-") or "other",
    }


# ---------------------------------------------------------------------------
# Discovery & Frontmatter
# ---------------------------------------------------------------------------

def discover_posts(section=None):
    """Find all */index.md files across all sections (or a specific section)."""
    dirs = [section] if section else SECTIONS
    posts = []
    for sec in dirs:
        sec_dir = ROOT / sec
        if sec_dir.is_dir():
            for md_file in sorted(sec_dir.glob("*/index.md")):
                posts.append(md_file)
    return posts


def parse_frontmatter(text):
    """Split YAML frontmatter from markdown body."""
    if text.startswith("---"):
        parts = text.split("---", 2)
        if len(parts) >= 3:
            meta = yaml.safe_load(parts[1])
            body = parts[2].strip()
            return meta, body
    return {}, text


# ---------------------------------------------------------------------------
# Annotated Text → SVG  (```text {annotate} blocks)
# ---------------------------------------------------------------------------

def process_annotate_blocks(body):
    """
    Convert annotate blocks into inline SVG diagrams.

    Syntax:
        ```text {annotate}
        Jeg har alltid likt å gå tur i fjellet om sommeren.
        ---
        fjellet | fjall (Old Norse) | the mountain
        sommeren | sumar (Old Norse) | the summer
        ```

    Each annotation line: word | etymology | translation
    Generates SVG with the sentence, highlighted words, connector lines,
    and annotation boxes below.
    """
    pattern = r"```(?:text|norwegian)?\s*\{annotate\}\n(.*?)```"

    def render_annotate(match):
        content = match.group(1).strip()
        if "---" in content:
            text_part, annot_part = content.split("---", 1)
        else:
            return f"<pre><code>{escape_html(content)}</code></pre>"

        sentence = text_part.strip()
        annotations = []
        for line in annot_part.strip().splitlines():
            line = line.strip()
            if not line or "|" not in line:
                continue
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 3:
                annotations.append({
                    "word": parts[0],
                    "etymology": parts[1],
                    "translation": parts[2],
                })
            elif len(parts) == 2:
                annotations.append({
                    "word": parts[0],
                    "etymology": "",
                    "translation": parts[1],
                })

        if not annotations:
            return f"<p>{escape_html(sentence)}</p>"

        return generate_annotate_html(sentence, annotations)

    return re.sub(pattern, render_annotate, body, flags=re.DOTALL)


def generate_annotate_html(sentence, annotations):
    """Generate HTML with text + right-margin annotation cards + connector lines."""
    import random
    # Rotating card colors (background, border-left accent)
    card_colors = [
        ("#1e3a5f", "#3b82f6"),   # blue
        ("#14412a", "#22c55e"),   # green
        ("#4a1420", "#e11d48"),   # red/rose
        ("#3b1249", "#a855f7"),   # purple
        ("#422006", "#f59e0b"),   # amber
        ("#134e4a", "#14b8a6"),   # teal
        ("#4a2512", "#ea580c"),   # orange
        ("#1e1b4b", "#6366f1"),   # indigo
        ("#3f1a0a", "#dc2626"),   # deep red
        ("#1a2e05", "#84cc16"),   # lime
    ]
    # Light mode card colors
    card_colors_light = [
        ("#dbeafe", "#2563eb"),
        ("#dcfce7", "#16a34a"),
        ("#ffe4e6", "#e11d48"),
        ("#f3e8ff", "#9333ea"),
        ("#fef3c7", "#d97706"),
        ("#ccfbf1", "#0d9488"),
        ("#ffedd5", "#ea580c"),
        ("#e0e7ff", "#4f46e5"),
        ("#fee2e2", "#dc2626"),
        ("#ecfccb", "#65a30d"),
    ]

    # Generate unique block ID
    block_id = f"anno-{random.randint(1000,9999)}"

    # Build highlighted text
    sentence_lower = sentence.lower()
    segments = []
    pos = 0
    sorted_anns = sorted(enumerate(annotations),
                         key=lambda x: sentence_lower.find(x[1]["word"].lower()))

    for orig_idx, ann in sorted_anns:
        word = ann["word"]
        idx = sentence_lower.find(word.lower(), pos)
        if idx == -1:
            continue
        if idx > pos:
            segments.append(escape_html(sentence[pos:idx]))
        color_idx = orig_idx % len(card_colors)
        _, accent = card_colors[color_idx]
        segments.append(
            f'<mark class="anno-hl" data-card="{block_id}-{orig_idx}" '
            f'style="--hl-color:{accent}">{escape_html(sentence[idx:idx+len(word)])}</mark>'
        )
        pos = idx + len(word)
    if pos < len(sentence):
        segments.append(escape_html(sentence[pos:]))

    text_html = "".join(segments)

    # Build annotation cards — alternate left and right
    left_cards = []
    right_cards = []
    for i, ann in enumerate(annotations):
        color_idx = i % len(card_colors)
        bg, accent = card_colors[color_idx]
        bg_light, _ = card_colors_light[color_idx]
        word = escape_html(ann["word"])
        trans = escape_html(ann.get("translation", ""))
        etym_raw = escape_html(ann.get("etymology", ""))
        side = "left" if i % 2 == 0 else "right"

        # Bold root words before quoted meanings: word "meaning" → <b>word</b> "meaning"
        etym = re.sub(
            r'([\w\-]+)(\s+&quot;)',
            r'<b>\1</b>\2',
            etym_raw
        ) if etym_raw else ""

        card = (
            f'<div class="anno-card" id="{block_id}-{i}" data-side="{side}" '
            f'style="--card-bg:{bg};--card-accent:{accent};--card-bg-light:{bg_light}">'
            f'<strong>{word}</strong>'
            f'<span class="anno-card-trans">&ldquo;{trans}&rdquo;</span>'
            + (f'<span class="anno-card-etym">{etym}</span>' if etym else '')
            + '</div>'
        )
        if side == "left":
            left_cards.append(card)
        else:
            right_cards.append(card)

    return (
        f'<div class="annotate-block" id="{block_id}">'
        f'<aside class="annotate-cards annotate-left">{"".join(left_cards)}</aside>'
        f'<div class="annotate-text"><p>{text_html}</p></div>'
        f'<aside class="annotate-cards annotate-right">{"".join(right_cards)}</aside>'
        f'<svg class="anno-lines"></svg>'
        f'</div>'
    )


# ---------------------------------------------------------------------------
# Code Execution
# ---------------------------------------------------------------------------

def execute_code_blocks(body, post_dir, no_exec=False):
    """
    Find executable code blocks (```python {show/hide} or ```r {show/hide}),
    execute them, and replace with output.
    """
    fig_counter = [0]
    table_counter = [0]

    def run_block(match):
        lang = match.group(1)
        visibility = match.group(2)
        code = match.group(3)

        if no_exec:
            if visibility == "show":
                return f'\n<pre><code class="language-{lang}">{escape_html(code.strip())}</code></pre>\n<p><em>(code execution skipped)</em></p>\n'
            else:
                return '\n<p><em>(code execution skipped)</em></p>\n'

        # Prepare figure output path
        fig_counter[0] += 1
        assets_dir = os.path.join(post_dir, "assets")
        os.makedirs(assets_dir, exist_ok=True)
        fig_name = f"fig_{fig_counter[0]:03d}.png"
        fig_path = os.path.join(assets_dir, fig_name)

        # Replace __BUILD_OUTPUT__ sentinel
        exec_code = code.replace("__BUILD_OUTPUT__", fig_path)

        # For Python, force non-interactive matplotlib backend
        if lang == "python" and "matplotlib" in exec_code:
            exec_code = "import matplotlib; matplotlib.use('Agg')\n" + exec_code

        # Write temp file and execute
        suffix = ".py" if lang == "python" else ".R"
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=suffix, dir=post_dir, delete=False
        ) as f:
            f.write(exec_code)
            tmp_path = f.name

        try:
            cmd = ["python", tmp_path] if lang == "python" else ["Rscript", tmp_path]
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=120, cwd=post_dir
            )
        except subprocess.TimeoutExpired:
            return '\n<div class="callout"><div class="callout-title">Error</div><p>Code execution timed out (120s limit).</p></div>\n'
        finally:
            os.unlink(tmp_path)

        # Build output HTML
        parts = []

        # Show code block if {show}
        if visibility == "show":
            parts.append(
                f'<pre><code class="language-{lang}">{escape_html(code.strip())}</code></pre>'
            )

        # Handle errors
        if result.returncode != 0:
            err = escape_html(result.stderr.strip())
            parts.append(
                f'<div class="callout"><div class="callout-title">Error</div><pre><code>{err}</code></pre></div>'
            )
            return "\n".join(parts)

        # Check if a figure was generated
        if os.path.exists(fig_path):
            parts.append(
                f'<div class="article-image"><img src="assets/{fig_name}" alt=""></div>'
            )
        else:
            fig_counter[0] -= 1  # no figure created, revert counter

        # Handle stdout
        stdout = result.stdout.strip()
        if stdout:
            if stdout.lstrip().startswith(("<table", "<div", "<TABLE", "<DIV")):
                # Assign table IDs
                def add_table_id(m):
                    table_counter[0] += 1
                    tid = f"table{table_counter[0]}"
                    tag = m.group(0)
                    if 'id=' not in tag:
                        return tag[:-1] + f' id="{tid}">'
                    return tag
                stdout = re.sub(r'<table[^>]*>', add_table_id, stdout, flags=re.IGNORECASE)
                # Strip pandas border="1" and inline style for clean CSS styling
                stdout = re.sub(r'\s*border="[^"]*"', '', stdout)
                stdout = re.sub(r'\s*style="text-align:\s*\w+;?"', '', stdout)
                parts.append(f'<div class="table-container">{stdout}</div>')
            else:
                parts.append(f"<pre><code>{escape_html(stdout)}</code></pre>")

        # Stderr warnings (non-fatal)
        if result.stderr.strip() and result.returncode == 0:
            pass  # suppress warnings in output

        return "\n".join(parts)

    pattern = r"```(python|r)\s*\{(show|hide)\}\n(.*?)```"
    body = re.sub(pattern, run_block, body, flags=re.DOTALL | re.IGNORECASE)

    # Process {annotate} blocks: Norwegian text with word annotations → inline SVG
    body = process_annotate_blocks(body)
    # Process ```math {annotate}``` blocks: an equation with \cssId anchors + margin
    # cards whose arrows point to parts of the formula (drawn by mathanno.js).
    body = process_math_annotate_blocks(body)
    return body, table_counter[0]


def process_math_annotate_blocks(body):
    r"""Render ```math {annotate}``` blocks: a display equation (whose parts are
    tagged with \cssId{id}{...}) plus annotation cards in the right margin.

    Syntax:
        ```math {annotate}
        V = \cssId{a1}{\pi(k,s)} - \cssId{a2}{\xi e} + \beta \cssId{a3}{E[V']}
        ---
        a1 | 当期经营利润
        a2 | 外部融资成本（ξ 为线性成本）
        a3 | 贴现的延续价值
        ```
    """
    pattern = r"```math\s*\{annotate\}\n(.*?)```"

    def render(match):
        content = match.group(1).strip()
        if "---" not in content:
            return f'\n<div class="mathanno-eq">$$\n{content}\n$$</div>\n'
        latex_part, annot_part = content.split("---", 1)
        latex = latex_part.strip()
        cards = []
        for line in annot_part.strip().splitlines():
            line = line.strip()
            if not line or "|" not in line:
                continue
            parts = [p.strip() for p in line.split("|")]
            tid = parts[0]
            zh = parts[1] if len(parts) > 1 else ""
            en = parts[2] if len(parts) > 2 else ""
            if tid:
                cards.append((tid, zh, en))
        if not cards:
            return f'\n<div class="mathanno-eq">$$\n{latex}\n$$</div>\n'

        def _expl(zh, en):
            # Bilingual card text (toggles with EN/中文) when an English part is given.
            if en:
                return (f'<span class="lang zh">{escape_html(zh)}</span>'
                        f'<span class="lang en">{escape_html(en)}</span>')
            return escape_html(zh)

        card_html = "".join(
            f'<div class="mathanno-card" data-target="{escape_html(tid)}">'
            f'<span class="mathanno-num">{i + 1}</span>{_expl(zh, en)}</div>'
            for i, (tid, zh, en) in enumerate(cards)
        )
        return (
            '\n<div class="mathanno-block">'
            f'<div class="mathanno-eq">$$\n{latex}\n$$</div>'
            f'<aside class="mathanno-cards">{card_html}</aside>'
            '<svg class="mathanno-lines"></svg>'
            '</div>\n'
        )

    return re.sub(pattern, render, body, flags=re.DOTALL)


def escape_html(text):
    """Escape HTML special characters."""
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


# ---------------------------------------------------------------------------
# Inline Word Annotations  (**word**`form` · *translation* · etymology)
# ---------------------------------------------------------------------------

def process_word_annotations(html):
    """
    Convert inline word annotations into styled tooltip spans.

    Input pattern in HTML (after markdown conversion):
        <strong>word</strong><code>form</code> · <em>translation</em> · etymology

    Output:
        <span class="anno-word" data-tip="form — translation (etymology)">word</span>
    """
    # After markdown→HTML, the pattern becomes:
    # <strong>word</strong><code>dict_form</code> · <em>translation</em> · etymology
    # Etymology contains <em> tags for italic foreign words, plus language
    # abbreviations, parentheticals, and connectors (+, /, ,, ;).
    # Strategy: match etymology as a sequence of segments, each ending with
    # <em>word</em> and optional (parenthetical), joined by connectors.

    pattern = (
        r'<strong>([^<]+)</strong>'           # group 1: displayed word
        r'<code>([^<]+)</code>'               # group 2: dictionary form
        r'\s*·\s*'                            # separator
        r'<em>([^<]+)</em>'                   # group 3: translation
        r'\s*·\s*'                            # separator
        r'('                                  # group 4: etymology
          r'(?:(?!<span|</p>).)*?'           #   prefix text (lang abbrev etc.)
          r'(?:<em>[^<]+</em>|<strong>[^<]+</strong>)' #   italic/bold foreign word
          r'(?:\s*(?:\([^)]*\)|"[^"]*"|&#822[01];[^&#]*&#822[01];))?' # optional (paren) or "quoted"
          r'(?:'                              #   additional segments:
            r'\s*[+/,;·]\s*'                  #     connector
            r'(?:(?!<span|</p>).)*?'         #     prefix text
            r'(?:<em>[^<]+</em>|<strong>[^<]+</strong>)' #   italic/bold foreign word
            r'(?:\s*(?:\([^)]*\)|"[^"]*"|&#822[01];[^&#]*&#822[01];))?' # optional (paren) or "quoted"
          r')*'                               #   zero or more
        r')'                                  # end group 4
    )

    def replace_anno(m):
        word = m.group(1)
        form = m.group(2).strip()
        trans = m.group(3).strip()
        etym_raw = (m.group(4) or "").strip().rstrip(",.")

        # Strip HTML tags from etymology for tooltip
        etym = re.sub(r'<[^>]+>', '', etym_raw).strip()

        # Build tooltip text — wraps naturally in CSS
        tip_parts = [form]
        if trans:
            tip_parts.append(f"— {trans}")
        if etym:
            tip_parts.append(f"({etym})")
        tip = " ".join(tip_parts)
        tip_escaped = tip.replace('"', '&quot;').replace("'", '&#39;')

        return f'<span class="anno-word" data-tip="{tip_escaped}">{word}</span>'

    return re.sub(pattern, replace_anno, html)


# ---------------------------------------------------------------------------
# Callout Processing
# ---------------------------------------------------------------------------

def process_callouts(html):
    """Convert > [!note] blockquotes into styled callout divs."""
    pattern = r"<blockquote>\s*<p>\[!(note|warning|tip|important)\]\s*\n?(.*?)</p>\s*</blockquote>"

    def replace_callout(match):
        callout_type = match.group(1).capitalize()
        content = match.group(2).strip()
        return (
            f'<div class="callout">'
            f'<div class="callout-title">{callout_type}</div>'
            f"<p>{content}</p>"
            f"</div>"
        )

    return re.sub(pattern, replace_callout, html, flags=re.DOTALL)


# ---------------------------------------------------------------------------
# TOC Generation
# ---------------------------------------------------------------------------

class HeadingExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self.headings = []
        self._current_tag = None
        self._current_text = ""

    def handle_starttag(self, tag, attrs):
        if tag in ("h2", "h3"):
            self._current_tag = tag
            self._current_text = ""

    def handle_data(self, data):
        if self._current_tag:
            self._current_text += data

    def handle_endtag(self, tag):
        if tag in ("h2", "h3") and self._current_tag == tag:
            self.headings.append((tag, self._current_text.strip()))
            self._current_tag = None


def generate_toc(html):
    """Extract h2/h3 headings and generate TOC HTML + add IDs to headings."""
    extractor = HeadingExtractor()
    extractor.feed(html)

    if not extractor.headings:
        return html, ""

    toc_items = []
    for tag, text in extractor.headings:
        slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
        # Add id to the heading in the HTML
        old = f"<{tag}>{text}</{tag}>"
        new = f'<{tag} id="{slug}">{text}</{tag}>'
        html = html.replace(old, new, 1)

        indent = '  ' if tag == "h3" else ''
        toc_items.append(f'{indent}<li><a href="#{slug}">{text}</a></li>')

    toc_html = "\n        ".join(toc_items)
    return html, toc_html


# ---------------------------------------------------------------------------
# Render Post
# ---------------------------------------------------------------------------

def render_post(md_path, no_exec=False):
    """Convert a markdown post to HTML."""
    post_dir = str(md_path.parent)
    slug = md_path.parent.name

    text = md_path.read_text(encoding="utf-8")
    meta, body = parse_frontmatter(text)

    title = meta.get("title", slug)
    author = meta.get("author", "Jun He")
    date = meta.get("date", datetime.now())
    tags = meta.get("tags", [])

    if isinstance(date, _dt.date) and not isinstance(date, datetime):
        date = datetime.combine(date, datetime.min.time())
    elif isinstance(date, str):
        date = datetime.strptime(date, "%Y-%m-%d")

    date_display = date.strftime("%B %d, %Y")
    date_short = date.strftime("%b %Y")

    # Source-paper card data (research posts): original title, authors, journal/year.
    vinfo = parse_venue(meta.get("venue", ""))

    # Execute code blocks
    body, table_count = execute_code_blocks(body, post_dir, no_exec=no_exec)

    # Protect LaTeX math from Markdown (so _, *, \ inside formulas survive). We
    # detect $$…$$, \[…\], \(…\), and inline $…$, then restore after conversion.
    # Inline $…$ is rewritten to \(…\) so MathJax never treats a price like "$100"
    # as math. To tell math from a $-amount, an inline span must (a) not open right
    # before a space or digit, (b) not close right before a digit, and (c) contain
    # a letter or backslash — so "$x$", "$\beta$", "$k_{jt}$" match but "$100" doesn't.
    # Protect fenced code blocks from the inline-math `$` detection below: R code
    # uses `$` for column access (e.g. `exchanges$exchange`), which the math regex
    # would otherwise mangle. Stash whole ``` fences now, run the math pass on the
    # remaining prose, then restore them before Markdown converts them normally.
    # MathJax skips <pre>/<code>, so restored `$` in code stays literal.
    _code = []

    def _stash_code(m):
        _code.append(m.group(0))
        return f"\x02CODE{len(_code) - 1}\x02"

    body = re.sub(r"```.*?```", _stash_code, body, flags=re.DOTALL)

    _math = []

    def _stash(m):
        _math.append(m.group(0))
        return f"\x01MATH{len(_math) - 1}\x01"

    body = re.sub(r"\$\$.+?\$\$", _stash, body, flags=re.DOTALL)
    body = re.sub(r"\\\[.+?\\\]", _stash, body, flags=re.DOTALL)
    body = re.sub(r"\\\(.+?\\\)", _stash, body, flags=re.DOTALL)
    body = re.sub(r"(?<![\\$\d])\$(?!\s)([^$\n]*?[A-Za-z\\][^$\n]*?)\$(?!\d)", _stash, body)
    # Also a tightly-delimited number, e.g. $0$, $0.4$, $50$ (math, not a $-amount):
    # both delimiters present, short numeric content, not adjacent to other digits.
    body = re.sub(r"(?<![\\$\d.])\$([0-9][0-9.,]{0,7})\$(?!\d)", _stash, body)

    # Restore fenced code (stashed before the math pass) so Markdown converts it.
    for _i, _c in enumerate(_code):
        body = body.replace(f"\x02CODE{_i}\x02", _c)

    # Convert markdown to HTML
    md = markdown.Markdown(extensions=["fenced_code", "tables", "attr_list", "md_in_html"])
    content_html = md.convert(body)

    # Restore math (inline single-$ → \(…\); display/other delimiters unchanged).
    for _i, _m in enumerate(_math):
        if _m.startswith("$$") or _m.startswith("\\[") or _m.startswith("\\("):
            _restored = _m
        else:  # inline $…$
            _restored = "\\(" + _m[1:-1] + "\\)"
        content_html = content_html.replace(f"\x01MATH{_i}\x01", _restored)

    # Process inline word annotations: **word**`form` · *translation* · etymology
    content_html = process_word_annotations(content_html)

    # Process callouts
    content_html = process_callouts(content_html)

    # Wrap standalone images in article-image div
    content_html = re.sub(
        r'<p>(<img [^>]+>)</p>',
        r'<div class="article-image">\1</div>',
        content_html,
    )

    # Generate TOC
    content_html, toc_html = generate_toc(content_html)

    # Detect tables for DataTables
    has_tables = "<table" in content_html.lower()
    table_ids = [f"table{i}" for i in range(1, table_count + 1)]

    # Detect annotate blocks
    has_annotate = "annotate-block" in content_html

    # Render template
    template = env.get_template("post.html")
    html = template.render(
        title=title,
        author=author,
        date_display=date_display,
        tags=tags,
        content=content_html,
        toc=toc_html,
        has_tables=has_tables,
        table_ids=table_ids,
        has_annotate=has_annotate,
        section=md_path.parent.parent.name,
        title_en=meta.get("title_en", ""),
        paper_authors=meta.get("paper_authors", ""),
        paper_authors_list=author_links(meta.get("paper_authors", "")),
        paper_journal=vinfo["journal"] if vinfo["journal"] != "Other" else "",
        paper_year=vinfo["art_year"],
    )

    # Write output
    out_path = md_path.parent / "index.html"
    out_path.write_text(html, encoding="utf-8")

    return {
        "slug": slug,
        "title": title,
        "date": date,
        "date_short": date_short,
        "tags": tags,
    }


# ---------------------------------------------------------------------------
# Build Listing
# ---------------------------------------------------------------------------

def build_listing(posts_meta, section="posts"):
    """Generate listing index.html for a section."""
    if section == "research":
        # Group by journal: by journal rank, then newest article first within each.
        posts_meta.sort(key=lambda p: (p.get("journal_rank", 500),
                                       -p.get("art_year", 0),
                                       -p.get("art_month", 0),
                                       p["date"].timestamp() * -1))
        # Per-journal totals, so the listing can cap at 3 and only show "more"
        # when a journal actually has extra posts.
        totals = {}
        for p in posts_meta:
            totals[p.get("journal_label", "")] = totals.get(p.get("journal_label", ""), 0) + 1
        for p in posts_meta:
            p["journal_total"] = totals.get(p.get("journal_label", ""), 0)
    else:
        posts_meta.sort(key=lambda p: p["date"], reverse=True)

    # Use section-specific template if it exists, else fall back to post_listing
    template_name = f"{section}_listing.html"
    try:
        template = env.get_template(template_name)
    except Exception:
        template = env.get_template("post_listing.html")

    section_title = {
        "posts": "Posts",
        "research": "Research",
        "data": "Data",
        "bergen": "Bergen",
    }.get(section, section.capitalize())

    html = template.render(posts=posts_meta, section_title=section_title)

    out_dir = ROOT / section
    out_dir.mkdir(exist_ok=True)
    out_path = out_dir / "index.html"
    out_path.write_text(html, encoding="utf-8")


def build_author_pages(posts_meta):
    """Generate one static page per paper author, listing the papers of theirs
    reviewed on the blog. The source-paper card links author names here.

    Stale author dirs (authors no longer referenced) are pruned so renamed/removed
    authors don't leave dangling pages.
    """
    authors = {}  # slug -> {"name": str, "posts": [meta, ...]}
    for p in posts_meta:
        for a in author_links(p.get("paper_authors", "")):
            slug = a["url"].rstrip("/").rsplit("/", 1)[-1]
            if not slug:
                continue
            authors.setdefault(slug, {"name": a["name"], "posts": []})
            authors[slug]["posts"].append(p)

    base = ROOT / "research" / "author"
    base.mkdir(parents=True, exist_ok=True)

    # Prune author dirs that are no longer referenced.
    for d in base.iterdir():
        if d.is_dir() and d.name not in authors:
            shutil.rmtree(d, ignore_errors=True)

    if not authors:
        return
    template = env.get_template("author_listing.html")
    for slug, info in authors.items():
        posts = sorted(info["posts"],
                       key=lambda p: (-p.get("art_year", 0), -p.get("art_month", 0),
                                      p["date"].timestamp() * -1))
        html = template.render(author=info["name"], posts=posts,
                               section_title=info["name"])
        out_dir = base / slug
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "index.html").write_text(html, encoding="utf-8")
    print(f"  Built {len(authors)} author page(s)")


def build_journal_pages(posts_meta):
    """Generate one static page per journal, listing all blog posts in that
    journal. The "more →" link beside each journal header on the listing
    points here. Stale journal dirs are pruned.
    """
    journals = {}  # slug -> {label, rank, posts}
    for p in posts_meta:
        slug = p.get("journal_slug")
        if not slug or slug == "other":
            continue
        journals.setdefault(slug, {"label": p.get("journal_label", ""),
                                   "rank": p.get("journal_rank", 500), "posts": []})
        journals[slug]["posts"].append(p)

    base = ROOT / "research" / "journal"
    base.mkdir(parents=True, exist_ok=True)
    for d in base.iterdir():
        if d.is_dir() and d.name not in journals:
            shutil.rmtree(d, ignore_errors=True)

    if not journals:
        return
    template = env.get_template("journal_listing.html")
    for slug, info in journals.items():
        posts = sorted(info["posts"],
                       key=lambda p: (-p.get("art_year", 0), -p.get("art_month", 0),
                                      p["date"].timestamp() * -1))
        html = template.render(journal=info["label"], posts=posts,
                               section_title=info["label"])
        out_dir = base / slug
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "index.html").write_text(html, encoding="utf-8")
    print(f"  Built {len(journals)} journal page(s)")


# ---------------------------------------------------------------------------
# Build All
# ---------------------------------------------------------------------------

def build_all(no_exec=False, single_post=None):
    """Build all pages across all sections, or a single page."""
    start = time.time()

    md_files = discover_posts()
    if not md_files:
        print("No pages found")
        return

    if single_post:
        md_files = [f for f in md_files if f.parent.name == single_post]
        if not md_files:
            print(f"Page '{single_post}' not found")
            return

    for md_path in md_files:
        section = md_path.parent.parent.name  # e.g. "posts", "bergen"
        print(f"  Building: {section}/{md_path.parent.name}")
        try:
            meta = render_post(md_path, no_exec=no_exec)
            meta["section"] = section
        except Exception as e:
            print(f"  ERROR: {e}")

    # Rebuild listings for each section
    for section in SECTIONS:
        sec_dir = ROOT / section
        if not sec_dir.is_dir():
            continue
        all_meta = []
        for md_path in discover_posts(section=section):
            text = md_path.read_text(encoding="utf-8")
            meta, _ = parse_frontmatter(text)
            date = meta.get("date", datetime.now())
            if isinstance(date, _dt.date) and not isinstance(date, datetime):
                date = datetime.combine(date, datetime.min.time())
            elif isinstance(date, str):
                date = datetime.strptime(date, "%Y-%m-%d")
            all_meta.append({
                "slug": md_path.parent.name,
                "title": meta.get("title", md_path.parent.name),
                "title_en": meta.get("title_en", ""),
                "paper_authors": meta.get("paper_authors", ""),
                "venue": meta.get("venue", ""),
                "category": meta.get("category", ""),
                "part": meta.get("part", ""),
                "order": meta.get("order", 0),
                "date": date,
                "date_short": date.strftime("%b %Y"),
                "section": section,
                **parse_venue(meta.get("venue", "")),
            })
        build_listing(all_meta, section=section)
        if all_meta:
            print(f"  Built {section} listing ({len(all_meta)} pages)")
        if section == "research":
            build_author_pages(all_meta)
            build_journal_pages(all_meta)

    elapsed = time.time() - start
    print(f"\nDone in {elapsed:.1f}s")


# ---------------------------------------------------------------------------
# Watch Mode
# ---------------------------------------------------------------------------

def watch_mode(no_exec=False):
    """Watch for .md file changes and rebuild."""
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler

    class RebuildHandler(FileSystemEventHandler):
        def __init__(self):
            self._last_build = 0

        def on_modified(self, event):
            if not event.src_path.endswith(".md"):
                return
            # Debounce: ignore events within 1 second
            now = time.time()
            if now - self._last_build < 1:
                return
            self._last_build = now

            slug = Path(event.src_path).parent.name
            print(f"\n  Changed: {slug}/index.md")
            try:
                build_all(no_exec=no_exec, single_post=slug)
            except Exception as e:
                print(f"  ERROR: {e}")

    # Initial full build
    print("Building all posts...")
    build_all(no_exec=no_exec)

    observer = Observer()
    for sec in SECTIONS:
        sec_dir = ROOT / sec
        if sec_dir.is_dir():
            observer.schedule(RebuildHandler(), str(sec_dir), recursive=True)
    observer.start()
    print("\nWatching for changes... (Ctrl+C to stop)")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()


# ---------------------------------------------------------------------------
# Serve Mode
# ---------------------------------------------------------------------------

def serve_mode(port=8080, no_exec=False, watch=False):
    """Build the site, then serve it over HTTP for browser preview.

    With --watch, also rebuilds on Markdown changes while serving.
    """
    import functools
    import threading
    from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

    print("Building site...")
    build_all(no_exec=no_exec)

    handler = functools.partial(SimpleHTTPRequestHandler, directory=str(ROOT))
    httpd = ThreadingHTTPServer(("127.0.0.1", port), handler)

    if watch:
        # Run the file watcher in a background thread so serving stays responsive.
        threading.Thread(target=watch_mode, kwargs={"no_exec": no_exec}, daemon=True).start()

    print(f"\nServing blog at http://localhost:{port}/")
    print(f"  Home:     http://localhost:{port}/")
    print(f"  Posts:    http://localhost:{port}/posts/")
    print(f"  Research: http://localhost:{port}/research/")
    print("Press Ctrl+C to stop.\n")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        httpd.shutdown()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Build blog posts from Markdown")
    parser.add_argument("--watch", action="store_true", help="Watch for changes")
    parser.add_argument("--serve", action="store_true", help="Build then serve over HTTP")
    parser.add_argument("--port", type=int, default=8080, help="Port for --serve (default 8080)")
    parser.add_argument("--post", type=str, help="Build a single post by slug")
    parser.add_argument(
        "--no-exec", action="store_true", help="Skip code block execution"
    )
    args = parser.parse_args()

    if args.serve:
        serve_mode(port=args.port, no_exec=args.no_exec, watch=args.watch)
    elif args.watch:
        watch_mode(no_exec=args.no_exec)
    else:
        print("Building posts...")
        build_all(no_exec=args.no_exec, single_post=args.post)


if __name__ == "__main__":
    main()
