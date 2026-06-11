---
layout: post
title: "From Make to Rake: Converting My Jekyll Build System"
date: 2026-06-11 12:00:00 +0400
categories: [ruby, automation]
tags: [make, rake, jekyll, build-tools]
published: true
---

My Jekyll blog has been using a Makefile for as long as I can remember. It's simple, it works, and honestly, I never thought much about it. But recently I've been writing more Ruby stuff, and it got me thinking: I'm already using `bundle exec jekyll` everywhere, so why not switch to Rake?

## The Original Makefile

Here's what I was working with:

```makefile
JEKYLL = bundle exec jekyll

.PHONY: help build serve dev clean install

help:
	@echo "Available commands:"
	@echo "  make build   - Build the site"
	@echo "  make serve   - Serve the site locally with auto-reload (dev)"
	@echo "  make dev     - Alias for 'make serve'"
	@echo "  make clean   - Remove the generated site and cache"
	@echo "  make install - Install Ruby dependencies"

build:
	$(JEKYLL) build

serve:
	$(JEKYLL) serve --watch --livereload

dev: serve

clean:
	$(JEKYLL) clean
	rm -rf _site_*

install:
	bundle install
```

Five targets. Nothing fancy. It's basically a shorthand so I don't have to type `bundle exec jekyll build` a million times.

## The Rakefile

I wanted a 1-to-1 mapping. Rake is Ruby's build system, and since this whole project is Ruby-based, it makes more sense than pulling in Make (which is a C tool originally). Here's what I ended up with:

```ruby
JEKYLL = "bundle exec jekyll"

desc "Build the site"
task :build do
  sh "#{JEKYLL} build"
end

desc "Serve the site locally with auto-reload"
task :serve do
  sh "#{JEKYLL} serve --watch --livereload"
end

desc "Alias for serve"
task dev: :serve

desc "Remove the generated site and cache"
task :clean do
  sh "#{JEKYLL} clean"
  rm_rf Dir["_site_*"]
end

desc "Install Ruby dependencies"
task :install do
  sh "bundle install"
end

task default: :build
```

Let me walk through the interesting bits.

### Variable

```ruby
JEKYLL = "bundle exec jekyll"
```

Same idea as the Makefile, just Ruby syntax. Constants in Ruby start with a capital letter. This keeps the command in one place so I'm not repeating it everywhere.

### Shell Commands

Make runs shell commands natively - that's its whole deal. Rake needs `sh()` to do the same thing:

```ruby
sh "#{JEKYLL} build"
```

Pretty clean. It prints the command and runs it. If the command fails, Rake stops with an error, just like Make does.

### Task Dependencies

Make has prerequisites (like `dev: serve`), and Rake has the same concept:

```ruby
task dev: :serve
```

This means running `rake dev` will first run the `serve` task. In Make, `make dev` does the same thing - it just runs the `serve` recipe directly since there's no recipe of its own.

### File Operations

For the `clean` target, I had to convert:

```makefile
rm -rf _site_*
```

to:

```ruby
rm_rf Dir["_site_*"]
```

Rake provides `rm_rf` (a wrapper around `FileUtils.rm_rf`) and `Dir[]` handles the glob pattern. This is actually better because `Dir["_site_*"]` expands the glob in Ruby rather than relying on the shell, which means it won't silently fail if the glob doesn't match anything (some shells return the literal `_site_*` string).

### Descriptions

```ruby
desc "Build the site"
task :build do
  ...
end
```

This is one feature I genuinely appreciate. Running `rake -T` gives me this:

```
rake build    # Build the site
rake clean    # Remove the generated site and cache
rake dev      # Alias for serve
rake install  # Install Ruby dependencies
rake serve    # Serve the site locally with auto-reload
```

No more maintaining a separate `help` target that I'll forget to update. Rake auto-discovers task descriptions. In Make, I had to manually echo everything, and you know the docs would get out of sync eventually.

### Default Task

```ruby
task default: :build
```

Rake doesn't have a built-in default target like Make does (where the first target is the default). You have to explicitly set it. Simple enough, just one line.

## What About Justfiles?

For my Rust projects, I've been using `just` with `justfile`s instead of Make. It's basically a modern Make that fixes a lot of the rough edges - no tabs required, recipes run with `#!/usr/bin/env` shells by default, and you get positional arguments out of the box. A typical `justfile` for a Rust project looks like:

```makefile
build:
	cargo build

release:
	cargo build --release

test:
	cargo test

fmt:
	cargo fmt --all

check:
	cargo check

lint:
	cargo clippy -- -D warnings
```

It's simpler than both Make and Rake, honestly.

## My Own Attempt: Makeover

I even wrote my own build tool in Python called [makeover](https://github.com/DavidBalishyan/makeover). It uses a `Buildfile` with a cleaner syntax, supports variables, target dependencies (DAG execution), smart rebuilds based on file modification times, and group-based listing. Here's what its `Buildfile` looks like:

```
[group: General]
# Default target runs all checks
all:
    ${py} ${src} --list

[group: Installation]
# Install binary to ~/.local/bin
install:
    echo "Installing ${bin} to ~/.local/bin..."
    mkdir -p ~/.local/bin
    cp ${src} ~/.local/bin/${bin}
    chmod +x ~/.local/bin/${bin}

[group: Utility]
# Clean up temporary files
clean:
    rm -rf __pycache__

lint:
    pylint ${src}
```

It worked well enough, but honestly, reinventing the wheel is more of a learning exercise than a practical solution. I don't actually reach for it over Rake or `just` day-to-day.

## One Tool Per Ecosystem

So that's the pattern I've settled on: Make for C/C++, `just` for Rust, Rake for Ruby. I've tried rolling my own, but the existing tools just do the job better. For this blog, which is a Ruby project through and through, Rake fits perfectly. The conventions match (Gemfile, Rakefile, `.rb` files), and I don't have to install anything extra since Rake ships with Ruby.

## Did It Change My Life?

Honestly? Not really. It's a build system for a static blog. But it does feel more natural in a Ruby project. `rake build` and `rake serve` look and feel like they belong in a Gemfile ecosystem.

The biggest practical win is `rake -T` - I can discover available commands without opening a file. That's small, but it's the kind of polish that makes a difference day-to-day.

If you're running a Jekyll site or any Ruby project with a Makefile, the switch is painless and takes maybe five minutes. Your `Makefile` and `Rakefile` can even live side by side while you transition, since they don't conflict.

The full Rakefile is [up on GitHub](https://github.com/DavidBalishyan/blog) if you want to check it out.
