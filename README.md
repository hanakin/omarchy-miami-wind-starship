# Miami Wind Starship Prompt

The colored bar above the line where you type, in the colors of the [Miami Wind Omarchy theme](https://github.com/hanakin/omarchy-miami-wind-theme). It shows your computer's name, the folder you're in, git status, whether the last command worked and how long it took, the tools a project uses, and the clock. It always fits the width of the terminal: when the window is narrow, the less important parts are left out.

## What you need

- [Starship](https://starship.rs). Omarchy comes with it.
- A [Nerd Font](https://www.nerdfonts.com) in your terminal, for the icons. Omarchy comes with one.
- Starship turned on in your shell. Omarchy's default zsh and bash settings already do this.

## Install

For each step: copy the line, paste it into your terminal, and press Enter.

1. Save your current prompt settings, in case you want them back:

   ```bash
   mv ~/.config/starship.toml ~/.config/starship.toml.bak
   ```

   If it says "No such file or directory", that's fine. Go to step 2.

2. Download the prompt:

   ```bash
   git clone --depth 1 https://github.com/hanakin/omarchy-miami-wind-starship ~/.config/starship
   ```

   If it says the folder "already exists and is not an empty directory", you already have a `~/.config/starship` folder. Rename it with `mv ~/.config/starship ~/.config/starship.bak`, then do this step again.

3. Turn on the Miami Wind prompt:

   ```bash
   ln -s ~/.config/starship/starship.toml ~/.config/starship.toml
   ```

4. Open a new terminal window to see it.

## Update

To get the newest version:

```bash
git -C ~/.config/starship pull
```

## Undo

1. Delete the link:

   ```bash
   rm ~/.config/starship.toml
   ```

2. Put your saved file back:

   ```bash
   mv ~/.config/starship.toml.bak ~/.config/starship.toml
   ```

   If it says "No such file or directory", you didn't have one before. That's fine.

3. Delete the download:

   ```bash
   rm -rf ~/.config/starship
   ```

4. Open a new terminal window.

## Test

```bash
python3 tests/test_prompt_width.py
```

## License

[MIT](LICENSE)
