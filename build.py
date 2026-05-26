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
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path

import markdown
import yaml
from jinja2 import Environment, FileSystemLoader

ROOT = Path(__file__).parent
POSTS_DIR = ROOT / "posts"
TEMPLATES_DIR = ROOT / "templates"

env = Environment(loader=FileSystemLoader(str(TEMPLATES_DIR)))


# ---------------------------------------------------------------------------
# Discovery & Frontmatter
# ---------------------------------------------------------------------------

def discover_posts():
    """Find all posts/*/index.md files."""
    posts = []
    for md_file in sorted(POSTS_DIR.glob("*/index.md")):
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
                parts.append(f'<div class="table-container">{stdout}</div>')
            else:
                parts.append(f"<pre><code>{escape_html(stdout)}</code></pre>")

        # Stderr warnings (non-fatal)
        if result.stderr.strip() and result.returncode == 0:
            pass  # suppress warnings in output

        return "\n".join(parts)

    pattern = r"```(python|r)\s*\{(show|hide)\}\n(.*?)```"
    body = re.sub(pattern, run_block, body, flags=re.DOTALL | re.IGNORECASE)
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

    if isinstance(date, str):
        date = datetime.strptime(date, "%Y-%m-%d")

    date_display = date.strftime("%B %d, %Y")
    date_short = date.strftime("%b %Y")

    # Execute code blocks
    body, table_count = execute_code_blocks(body, post_dir, no_exec=no_exec)

    # Convert markdown to HTML
    md = markdown.Markdown(extensions=["fenced_code", "tables", "attr_list"])
    content_html = md.convert(body)

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

def build_listing(posts_meta):
    """Generate posts/index.html from collected metadata."""
    posts_meta.sort(key=lambda p: p["date"], reverse=True)

    template = env.get_template("post_listing.html")
    html = template.render(posts=posts_meta)

    out_path = POSTS_DIR / "index.html"
    out_path.write_text(html, encoding="utf-8")


# ---------------------------------------------------------------------------
# Build All
# ---------------------------------------------------------------------------

def build_all(no_exec=False, single_post=None):
    """Build all posts or a single post."""
    start = time.time()

    md_files = discover_posts()
    if not md_files:
        print("No posts found (looking for posts/*/index.md)")
        return

    if single_post:
        md_files = [f for f in md_files if f.parent.name == single_post]
        if not md_files:
            print(f"Post '{single_post}' not found")
            return

    posts_meta = []
    for md_path in md_files:
        print(f"  Building: {md_path.parent.name}")
        try:
            meta = render_post(md_path, no_exec=no_exec)
            posts_meta.append(meta)
        except Exception as e:
            print(f"  ERROR: {e}")

    # If building all posts, regenerate listing
    if not single_post:
        build_listing(posts_meta)
        print(f"  Built posts listing ({len(posts_meta)} posts)")
    else:
        # Rebuild listing with all posts (not just the single one)
        all_meta = []
        for md_path in discover_posts():
            text = md_path.read_text(encoding="utf-8")
            meta, _ = parse_frontmatter(text)
            date = meta.get("date", datetime.now())
            if isinstance(date, str):
                date = datetime.strptime(date, "%Y-%m-%d")
            all_meta.append({
                "slug": md_path.parent.name,
                "title": meta.get("title", md_path.parent.name),
                "date": date,
                "date_short": date.strftime("%b %Y"),
            })
        build_listing(all_meta)

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
    observer.schedule(RebuildHandler(), str(POSTS_DIR), recursive=True)
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
