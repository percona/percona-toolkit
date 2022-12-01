#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import os
sys.path.append(os.path.abspath("../"))
from conf import *
extensions.append('sphinx_gitstamp')
extensions.append('sphinx_copybutton')
html_sidebars['**']=['globaltoc.html', 'searchbox.html', 'localtoc.html', 'logo-text.html']
html_theme = 'sphinx_material'
html_theme_options = {
    'base_url': 'http://bashtage.github.io/sphinx-material/',
    'repo_url': 'https://github.com/percona/percona-toolkit',
    'repo_name': 'percona/percona-toolkit',
    'color_accent': 'grey',
    'color_primary': 'orange',
    'globaltoc_collapse': True,
    'version_dropdown': True
}
html_logo = '../_static/percona-logo.svg'
html_favicon = '../_static/percona_favicon.ico'
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

