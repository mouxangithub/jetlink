"""
Copyright (c) 2026-, Zeph Leggett.

This file is part of jetlink and is licensed under the MIT License.
See the LICENSE file in the root directory for more details.

The Jetson's web page is one HTML file whose inline script draws all of it:
a single syntax error and nothing on the page runs. v0.8.11 shipped one, an
apostrophe in a single-quoted string, and the Swift tests only read the page
as text. node parses it here, without running it.
"""
from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest

PAGE = Path(__file__).resolve().parents[1] / 'JetlinkKit/Sources/JetlinkStatusPage/Resources/index.html'


@pytest.mark.skipif(shutil.which('node') is None, reason='node is not installed')
def test_the_pages_script_parses(tmp_path):
  scripts = re.findall(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', PAGE.read_text(), re.S)
  assert scripts, 'the page has no inline script'
  for i, script in enumerate(scripts):
    path = tmp_path / f'script{i}.js'
    path.write_text(script)
    result = subprocess.run(['node', '--check', str(path)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
