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
