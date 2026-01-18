# Makefile for Jekyll Blog

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
