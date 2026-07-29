---
layout: post
title: "My Dotfiles, Six Months Later"
date: 2026-07-31 12:00:00 +0400
categories: [linux]
tags: [dotfiles, bspwm, neovim, zsh, debian]
published: true
---

In January I wrote about [my dotfiles setup]({% post_url 2026-01-25-dotfiles %}). I had recently settled on Neovim, replaced Oh My Zsh with a hand-written `.zshrc`, and picked bspwm after trying almost every tiling window manager that looked interesting.

Six months later, the repo is much larger. Some parts have been rewritten completely. I also added enough installers and helper scripts that calling it a collection of config files feels slightly dishonest.

The funny part is that my actual desktop has become less experimental. I still try new terminals and keep old window manager configs around, but the machine I sit down at every day is Debian, bspwm, `st`, Zsh, tmux, and Neovim.

## I am only using bspwm

The `wm/other/` directory contains configs for i3, Sway, Waybar, and Wofi. They are not active, and I do not rotate between them. They survived earlier experiments because deleting a working config feels wasteful and because I sometimes want to steal an old keybinding from myself.

bspwm is my only window manager and my only desktop session.

I still like the same thing about it that I mentioned in January: bspwm manages windows, while sxhkd manages keybindings. There is no large configuration framework between me and either program. `bspwmrc` is a shell script, and `sxhkdrc` is a readable list of keys and commands.

The basic controls have barely changed:

```text
Super + Return          open st
Super + h/j/k/l         move focus
Super + Shift + h/j/k/l swap windows
Super + 1..0            switch workspaces
Super + d               open rofi
Super + q               close a window
```

What changed is everything around those controls. My bspwm session now starts sxhkd, dunst, CopyQ, picom, Polybar, `xss-lock`, and autorandr. It restores my monitor layout, starts a wallpaper with `feh`, enables Num Lock, and remaps Caps Lock to Escape. The keyboard setup includes US, Armenian, and Russian layouts with `Alt+Shift` switching between them.

I use ten desktops, one-pixel borders, three-pixel gaps, and focus follows the pointer. Pavucontrol, Blueman, and the NetworkManager editor open floating. Zen opens on desktop 2. None of this is clever, which is probably why it has stayed.

## Building a desktop out of small programs

bspwm is only the window manager. The rest of the desktop is a collection of programs that happen to share a Tokyo Night theme.

Polybar shows bspwm workspaces, the active window, date and time, audio, brightness, night light, network, Bluetooth, battery, and the tray. The network, Bluetooth, and night-light modules use small shell scripts instead of trying to make Polybar do everything itself.

Rofi handles application launching, command execution, window switching, file browsing, and the power menu. Dunst handles normal notifications plus the volume and brightness indicators. Picom adds shadows, fading, rounded corners, and blur. Gammastep handles the night light.

The lock screen got much more attention than a lock screen probably deserves. `xss-lock` runs it before suspend and after the machine has been idle. A script turns my wallpaper into a blurred, darkened image and passes it to `i3lock-color`, with a Tokyo Night ring and a clock on top. If only normal i3lock is available, it falls back to a plain background so the machine still locks.

This is the closest I have come to making my own desktop environment. I did not write the important programs. I just chose the pieces, connected them with shell scripts, and made the colors agree.

## I keep trying terminals and returning to st

The repo is misleading here too. It has configs for Alacritty, Ghostty, WezTerm, Kitty, Rio, and Foot. Their presence does not mean I use six terminal emulators.

I use my [patched build of st](https://github.com/DavidBalishyan/st). `Super+Return` launches it, `bspwmrc` exports it as the terminal, and the desktop installer builds it from source. My build has scrollback, ligatures, box drawing, alpha support, undercurls, fallback fonts, and the anysize patch. It uses JetBrains Mono Nerd Font and the same Tokyo Night palette as the rest of the desktop.

Every so often I install a new terminal, spend an evening making it look right, and then go back to `st`. That is why the Kitty and Rio configs are still fresh even though neither is my daily terminal. They are experiments, not a list of recommendations.

tmux still does the work I would otherwise ask the terminal to do. It opens splits in the current directory, uses Vim-style navigation, starts window numbering at 1, and has its own Tokyo Night status line. Keeping multiplexing in tmux also makes the terminal emulator less important.

## Neovim after Kickstart

In the first post I said my Neovim config started with `kickstart.nvim`. It did, but there is much less Kickstart left now.

The old config used `lazy.nvim` and kept most of the setup in one large file. In May I reorganized it into `lua/core/`, `lua/lsp/`, and `lua/plugins/`. Plugins now use Neovim's built-in `vim.pack`, so there is no separate plugin manager.

Telescope survived the rewrite. So did LSP support, Blink completion, Gitsigns, Oil, Neo-tree, Which Key, Lualine, and the other tools I had become used to. The difference is that I can now find a plugin's setup without searching through a 500-line `init.lua`.

I also stopped using Mason as another layer around language servers. The LSP config uses Neovim's built-in client directly. A small installer module checks whether each server executable exists and tells me the command I can use to install it. It knows about the languages I regularly encounter, including C and C++, Lua, Python, TypeScript, Go, Rust, Ruby, PHP, Nim, and Zig.

## A setup script became a dotfile manager

In January I described the management side as "a simple Git repo." Git is still underneath it, but the installation side outgrew a pile of `ln -s` commands.

I wrote [dfm](https://github.com/DavidBalishyan/dfm) and moved the main setup into `manifest.dfmc`. Each section describes a component, the packages it may need, the source and destination of its config, and a condition for enabling it.

For example, the Neovim entry is roughly this:

```ini
[nvim]
desc = Neovim editor (native vim.pack, no lazy.nvim)
packages.apt = neovim
packages.brew = neovim
packages.pacman = neovim
source = nvim -> ~/.config/nvim
condition = command:nvim
```

The manifest has entries for editors, shells, tmux, terminal emulators, Yazi, system-info tools, and display managers. It records package names for several package managers instead of assuming every machine looks exactly like my Debian laptop.

The bspwm desktop keeps its own installer under `wm/install.sh`. That setup is deliberately Debian-focused because it has more work to do than linking files. It installs the desktop programs, downloads JetBrains Mono Nerd Font, builds `i3lock-color`, builds my fork of `st`, and links the active desktop configs into `~/.config`.

The old `setup.sh`, Makefile, and justfile are still present. This repository has layers from several generations of "I should clean up my dotfiles." I have accepted that the cleanup tools will also need cleaning.

## Zsh stayed boring, in a good way

I still use Zsh without Oh My Zsh. Plugins are sourced directly from `~/.zsh/plugins`, and the list is small enough that I know why each one is there: completions, autosuggestions, syntax highlighting, alias reminders, and a few language-specific helpers.

The shell uses vi mode, Starship when it is installed, `zoxide` for directory jumping, and fzf's Zsh integration. Most of the file is ordinary aliases, paths, and checks that only enable integrations when their commands exist.

The repo has also collected small scripts for screenshots, audio control, network information, Git overviews, project setup, and other things I got tired of typing twice. Some are polished enough to reuse. Some make sense only on my machine. That is normal for dotfiles.

**Note:** The repo will probably keep accumulating configs for software I tried for two days. That is fine. If you want to know what I actually use, follow the bspwm startup script and sxhkd keybindings. Right now, they both lead to the same setup I chose in January, only much more finished.

The current dotfiles are on [GitHub](https://github.com/DavidBalishyan/dotfiles).
