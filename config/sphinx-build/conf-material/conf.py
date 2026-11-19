#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import os
sys.path.append(os.path.abspath("../"))
from conf import *
extensions.append('sphinx_immaterial')
html_sidebars['**']=['globaltoc.html', 'searchbox.html', 'localtoc.html', 'logo-text.html']
html_theme = 'sphinx_immaterial'
html_theme_options = {
    'site_url': 'https://docs.percona.com/percona-toolkit/',
    'repo_url': 'https://github.com/percona/percona-toolkit',
    'repo_name': 'percona/percona-toolkit',
    'edit_uri': 'edit/3.x/docs/',
    'globaltoc_collapse': True,
    'font': False,
    "features": [
        "navigation.top",
        "navigation.footer",
    ],
    "palette": [
        {
            "media": "(prefers-color-scheme)",
            "toggle": {
                "icon": "material/brightness-auto",
                "name": "Switch to light mode",
            },
        },
        {
            "media": "(prefers-color-scheme: light)",
            "scheme": "default",
            "primary": "deep-purple",
            "accent": "light-blue",
            "toggle": {
                "icon": "material/lightbulb",
                "name": "Switch to dark mode",
            },
        },
        {
            "media": "(prefers-color-scheme: dark)",
            "scheme": "slate",
            "primary": "deep-purple",
            "accent": "light-blue",
            "toggle": {
                "icon": "material/lightbulb-outline",
                "name": "Switch to system preference",
            },
        },
    ],
    'version_dropdown': True,
    'icon': {
        "repo": "fontawesome/brands/github",
        "edit": "material/file-edit-outline",
    },
}
html_logo = '../_static/percona-logo.svg'
html_favicon = '../_static/percona-favicon.svg'
pygments_style = 'emacs'
gitstamp_fmt = "%b %d, %Y"
# Specify the text pattern that won't be copied with the code block contents
copybutton_prompt_text = '$'
# Add any paths that contain templates here, relative to this directory.
templates_path = ['../_static/_templates/theme']
#html_last_updated_fmt = ''
# Path to custom css files. These will override the default css attribute if they exist
html_css_files = [
    '../_static/css/material.css',
]

# llms.txt, llms-full.txt and a .md copy of every page, for AI agents.
# https://github.com/NVIDIA/sphinx-llm
extensions.append('sphinx_llm.txt')
llms_txt_description = (
    'Percona Toolkit is a collection of command-line tools for MySQL, MongoDB and '
    'PostgreSQL administration: query analysis, online schema changes, replication '
    'checks, data archiving and system summaries. Each page below is also available '
    'as markdown. For the documentation of all Percona products, see '
    'https://docs.percona.com/llms.txt.'
)
markdown_http_base = 'https://docs.percona.com/percona-toolkit'
llms_txt_suffix_mode = 'replace'  # pt-archiver.html -> pt-archiver.md
llms_txt_full_build = True  # also llms-full.txt, all pages in one file

# sphinx-llm builds the .md pages in a second Sphinx run with this tag. The theme
# turns notes into nodes the markdown builder can't write, so leave it out there.
if tags.has('sphinx_llm_markdown'):  # noqa: F821 (Sphinx sets tags)
    extensions.remove('sphinx_immaterial')


def _unbold_section_titles(app, doctree):
    """Tool pages have titles like **pt-archiver** (from the POD). Keep the plain name."""
    from docutils import nodes

    for title in doctree.findall(nodes.title):
        for strong in list(title.findall(nodes.strong)):
            index = strong.parent.index(strong)
            strong.parent[index : index + 1] = strong.children


LLMS_TXT_POINTER = (
    '> For the complete Percona Toolkit documentation index, see '
    '[llms.txt](https://docs.percona.com/percona-toolkit/llms.txt).\n\n'
)


def _add_llms_txt_pointer(app, exception):
    """Start each .md page with a pointer to llms.txt, so an agent on one page finds the index.

    Runs after sphinx-llm has written llms.txt (its build-finished handlers have
    priority 100 and 101), so the page descriptions there stay the page's own text.
    """
    if exception is not None or app.builder.format != 'html':
        return
    from pathlib import Path

    for page in Path(app.outdir).glob('**/*.md'):
        text = page.read_text(encoding='utf-8')
        if not text.startswith(LLMS_TXT_POINTER):
            page.write_text(LLMS_TXT_POINTER + text, encoding='utf-8')


def _classifiers_to_text(app, doctree):
    """Keep definition-list classifiers ("csv : Dump rows ...") in the markdown, which drops them."""
    from docutils import nodes

    for classifier in list(doctree.findall(nodes.classifier)):
        classifier.replace_self(nodes.Text(' : ' + classifier.astext()))


def setup(app):
    app.connect('doctree-read', _unbold_section_titles)
    if app.tags.has('sphinx_llm_markdown'):
        app.connect('doctree-read', _classifiers_to_text)
    app.connect('build-finished', _add_llms_txt_pointer, priority=900)
