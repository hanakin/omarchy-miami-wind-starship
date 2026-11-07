"""Check the prompt's top bar never renders wider than the terminal.

starship.toml runs ~/.config/starship/bar.sh, and this repo is installed at
~/.config/starship, so the fake HOME links that path to this repo.
Run with: python3 tests/test_prompt_width.py
"""
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRANCH = 'feature/a-long-branch-name-that-keeps-going'


@unittest.skipUnless(shutil.which('starship') and shutil.which('git'), 'needs starship and git')
class PromptWidthTests(unittest.TestCase):
    def bar(self, home, cwd, width, *flags, **overrides):
        env = dict(os.environ, HOME=str(home), STARSHIP_CONFIG=str(ROOT / 'starship.toml'),
                   STARSHIP_SHELL='sh', MIAMI_WIND_COLS=str(width), PWD=str(cwd))
        env.update(overrides)
        out = subprocess.run(['starship', 'prompt', f'--terminal-width={width}', *flags],
                             cwd=cwd, env=env, capture_output=True, text=True, check=True).stdout
        return re.sub(r'\x1b\[[0-9;]*m', '', out).strip('\n').split('\n')[0]

    def test_bar_fits_terminal_width(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            (home / '.config').mkdir()
            (home / '.config/starship').symlink_to(ROOT)
            repo = home / 'project'
            repo.mkdir()
            (repo / 'package.json').write_text('{"version": "1.2.3"}')
            subprocess.run(['git', 'init', '-q', '-b', BRANCH], cwd=repo, check=True)
            for cwd in (home, repo):
                for width in (60, 80, 100, 200):
                    with self.subTest(cwd=cwd.name, width=width):
                        self.assertLessEqual(len(self.bar(home, cwd, width)), width)
            self.assertIn('PM', self.bar(home, repo, 200).replace('AM', 'PM'))
            self.assertIn('1.2.3', self.bar(home, repo, 200))
            self.assertIn(BRANCH, self.bar(home, repo, 200))
            # Status and duration reach the right strip only through starship's own arguments.
            self.assertIn(' 1 ', self.bar(home, repo, 200, '--status=1'))
            self.assertNotIn(' 1 ', self.bar(home, repo, 200, '--status=0'))
            self.assertIn(' 5s ', self.bar(home, repo, 200, '--cmd-duration=5000'))
            self.assertNotIn(' 2s ', self.bar(home, repo, 200, '--cmd-duration=2000'))

    def test_status_and_duration_without_proc(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            scripts = home / '.config/starship'
            scripts.mkdir(parents=True)
            # Hide only the renderer's /proc reads; Linux ps still needs /proc.
            source = (ROOT / 'bar.sh').read_text()
            (scripts / 'bar.sh').write_text(source.replace('/proc/', str(home / 'no-proc') + '/'))
            for status in (0, 1):
                with self.subTest(status=status):
                    bar = self.bar(home, home, 200, f'--status={status}',
                                   '--cmd-duration=5000', MIAMI_WIND_COLS='')
                    self.assertEqual(len(bar), 200)
                    self.assertIn(' 5s ', bar)
                    self.assertEqual(' 1 ' in bar, status == 1)

    def test_locale_without_c_utf8(self):
        locales = subprocess.check_output(['locale', '-a'], text=True)
        if not re.search(r'^en_US\.utf-?8$', locales, re.IGNORECASE | re.MULTILINE):
            self.skipTest('needs en_US.UTF-8')
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            (home / '.config').mkdir()
            (home / '.config/starship').symlink_to(ROOT)
            binaries = home / 'bin'
            binaries.mkdir()
            locale = binaries / 'locale'
            locale.write_text("#!/bin/sh\nprintf 'C\\nPOSIX\\nen_US.UTF-8\\n'\n")
            locale.chmod(0o755)
            wc = binaries / 'wc'
            wc.write_text('#!/bin/sh\nprintf "%s\\n" "$LC_ALL" >> "$HOME/wc-locales"\n'
                          f'exec "{shutil.which("wc")}" "$@"\n')
            wc.chmod(0o755)
            for width in (60, 200):
                with self.subTest(width=width):
                    self.assertEqual(len(self.bar(home, home, width,
                                     PATH=str(binaries) + os.pathsep + os.environ['PATH'])), width)
            self.assertEqual(set((home / 'wc-locales').read_text().splitlines()), {'en_US.UTF-8'})


if __name__ == '__main__':
    unittest.main()
