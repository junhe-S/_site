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
SECTIONS = ["posts", "research", "data", "bergen"]

env = Environment(loader=FileSystemLoader(str(TEMPLATES_DIR)))


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
    return body, table_counter[0]


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
          r'(?:(?!<strong>|</p>).)*?'         #   prefix text (lang abbrev etc.)
          r'<em>[^<]+</em>'                   #   italic foreign word
          r'(?:\s*\([^)]*\))?'               #   optional parenthetical
          r'(?:'                              #   additional segments:
            r'\s*[+/,;·]\s*'                  #     connector
            r'(?:(?!<strong>|</p>).)*?'       #     prefix text
            r'<em>[^<]+</em>'                 #     italic foreign word
            r'(?:\s*\([^)]*\))?'             #     optional parenthetical
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

    # Execute code blocks
    body, table_count = execute_code_blocks(body, post_dir, no_exec=no_exec)

    # Convert markdown to HTML
    md = markdown.Markdown(extensions=["fenced_code", "tables", "attr_list"])
    content_html = md.convert(body)

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
                "date": date,
                "date_short": date.strftime("%b %Y"),
                "section": section,
            })
        build_listing(all_meta, section=section)
        if all_meta:
            print(f"  Built {section} listing ({len(all_meta)} pages)")

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
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Build blog posts from Markdown")
    parser.add_argument("--watch", action="store_true", help="Watch for changes")
    parser.add_argument("--post", type=str, help="Build a single post by slug")
    parser.add_argument(
        "--no-exec", action="store_true", help="Skip code block execution"
    )
    args = parser.parse_args()

    if args.watch:
        watch_mode(no_exec=args.no_exec)
    else:
        print("Building posts...")
        build_all(no_exec=args.no_exec, single_post=args.post)


if __name__ == "__main__":
    main()
