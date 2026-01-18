# 🌙 David's Minimalist Blog

A clean, fast, and calm Jekyll blog featuring a customized **Gruvbox Dark** aesthetic.

![Jekyll](https://img.shields.io/badge/Jekyll-CC0000?style=for-the-badge&logo=jekyll&logoColor=white)
![Ruby](https://img.shields.io/badge/Ruby-CC342D?style=for-the-badge&logo=ruby&logoColor=white)
![Sass](https://img.shields.io/badge/Sass-CC6699?style=for-the-badge&logo=sass&logoColor=white)

## ✨ Features

- **Gruvbox Dark Palette**: A soothing, high-contrast dark theme optimized for readability.
- **Snappy Animations**: Subtle fade-in effects and smooth transitions for a premium feel.
- **Optimized Typography**: Clean, minimal layout with focus on content.
- **Custom Syntax Highlighting**: Fully integrated Gruvbox colors for code snippets.
- **Developer-Friendly**: Includes a `Makefile` for streamlined development workflows.

## 🚀 Getting Started

### Prerequisites

- Ruby & Bundler
- Jekyll

### Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/DavidBalishyan/blog.git
   cd blog
   ```

2. Install dependencies:

   ```bash
   make install
   ```

3. Run the development server:
   ```bash
   make dev
   ```
   The blog will be available at `http://localhost:4000/blog/`.

## 🛠️ Development

This project uses a `Makefile` to handle common tasks:

- `make build`: Generate the static site in `_site/`.
- `make serve`: Start the local dev server with livereload.
- `make clean`: Remove build artifacts and cache.
- `make install`: Install required Gems.

## 📂 Structure

- `_posts/`: Markdown files for your blog posts.
- `_includes/`: Reusable HTML components.
- `_layouts/`: Page templates.
- `assets/main.scss`: The primary stylesheet where the Gruvbox theme and animations are defined.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
