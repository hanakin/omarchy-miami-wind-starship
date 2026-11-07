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
    def bar(self, home, cwd, width, *flags):
        env = dict(os.environ, HOME=str(home), STARSHIP_CONFIG=str(ROOT / 'starship.toml'),
                   STARSHIP_SHELL='sh', MIAMI_WIND_COLS=str(width), PWD=str(cwd))
        out = subprocess.run(['starship', 'prompt', '--terminal-width', str(width), *flags],
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


if __name__ == '__main__':
    unittest.main()
