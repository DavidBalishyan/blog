---
layout: post
title: "Auto-Syncing My Repos from GitHub to Codeberg"
date: 2026-02-08 21:44:00 +0400
categories: [git, automation]
tags: [github, codeberg, github-actions, ci-cd]
published: true
---

So I recently decided to start mirroring my GitHub repos to Codeberg. Why? Honestly, I just don't love the idea of having all my code in one place. Plus, I wanted to support a platform that's actually community-driven and cares about open source.

The cool part is that I didn't want to manually push to both places every time. That would get old fast. Instead, I set up GitHub Actions to do it automatically, and it's been working perfectly.

## Why Codeberg?

If you haven't heard of [Codeberg](https://codeberg.org), it's basically a non-profit alternative to GitHub. It runs on Forgejo (which is a fork of Gitea), and the whole thing is community-run. No corporate overlords, no weird policy changes out of nowhere.

I'm not abandoning GitHub or anything, but having my stuff mirrored means:

- I'm not completely dependent on one platform
- My code stays accessible even if GitHub has issues
- I'm supporting open-source infrastructure

Win-win.

## How I Set It Up

Turns out it's actually super easy with GitHub Actions. Here's the workflow file I'm using:

```yaml
name: Mirror to Codeberg

on:
  push:
    branches:
      - main

jobs:
  mirror:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repo
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.CODEBERG_SSH_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan codeberg.org >> ~/.ssh/known_hosts

      - name: Mirror push to Codeberg
        run: |
          git remote add codeberg git@codeberg.org:DavidBalishyan/betterfetch.git
          git push --mirror codeberg
```

## Breaking It Down

Let me walk you through what this thing actually does:

### The Trigger

```yaml
on:
  push:
    branches:
      - main
```

Pretty straightforward - whenever I push to `main`, the workflow kicks off. If your default branch is named something else, just swap that out.

### Fetching the Repo

```yaml
- name: Checkout repo
  uses: actions/checkout@v4
  with:
    fetch-depth: 0
```

This grabs the repo, but here's the important bit: `fetch-depth: 0` means it pulls the _entire_ git history. By default, GitHub Actions only does a shallow clone, but we need everything to properly mirror the repo.

### SSH Setup

```yaml
- name: Setup SSH
  run: |
    mkdir -p ~/.ssh
    echo "${{ secrets.CODEBERG_SSH_KEY }}" > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    ssh-keyscan codeberg.org >> ~/.ssh/known_hosts
```

This part sets up SSH authentication. It:

- Creates the `.ssh` directory
- Drops in the private key from GitHub Secrets
- Sets the right permissions (SSH is picky about this - the key needs to be readable only by younking about diversifying where your code lives, this is probably the easiest way to do it.)
- Adds Codeberg's host key so we don't get prompted about unknown hosts

### The Actual Mirroring

```yaml
- name: Mirror push to Codeberg
  run: |
    git remote add codeberg git@codeberg.org:DavidBalishyan/betterfetch.git
    git push --mirror codeberg
```

Finally, we add Codeberg as a remote and push with `--mirror`. That flag is doing a lot of heavy lifting - it pushes everything (all branches, all tags) and keeps the repos perfectly in sync. If I delete a branch on GitHub, the `--mirror` flag will delete it on Codeberg too.

## Setting This Up Yourself

If you want to do the same thing, here's what you need to do:

### 1. Generate an SSH Key

If you don't already have one:

```bash
ssh-keygen -t ed25519 -C "github-actions@your-repo"
```

Just hit enter for the default location, and you can skip the passphrase (since this is only for GitHub Actions).

### 2. Add the Public Key to Codeberg

Go into your Codeberg settings, find the SSH Keys section, and paste in your public key (the one from `id_ed25519.pub`).

### 3. Add the Private Key to GitHub

This is the secret sauce:

- Head to your GitHub repo settings
- Go to Secrets and variables -> Actions
- Create a new secret called `CODEBERG_SSH_KEY`
- Paste in your private key (from `id_ed25519`)

### 4. Create the Workflow

Save the workflow YAML above as `.github/workflows/mirror-to-codeberg.yml` in your repo. Make sure to update the Codeberg URL to match your username and repo name.

### 5. Push and Watch

Commit and push everything to GitHub. If you set it up right, you should see the workflow run in the Actions tab, and your Codeberg repo should update automatically.

## Final Thoughts

I've been using this for a bit now and it just works. Every push to GitHub shows up on Codeberg within seconds, completely automatically. No extra steps, no remembering to push twice, nothing.

Plus, the whole setup is version-controlled right there in the repo, so if I ever need to adjust something or set this up for another project, it's trivial.

If you've been thinking about diversifying where your code lives, this is probably the easiest way to do it.


