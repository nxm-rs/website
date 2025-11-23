# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Zola static site for Nexum (nxm.rs), a Web3 project focused on decentralized browser extensions and storage. The site uses a customized version of the Apollo theme and is deployed to GitHub Pages.

## Build & Development Commands

### Building the site
```bash
# Build the site (outputs to public/ directory)
zola build

# Build with drafts included
zola build --drafts

# Serve locally with live reload (default: http://127.0.0.1:1111)
zola serve

# Serve with drafts visible
zola serve --drafts
```

### Formatting
```bash
# Format all files according to treefmt.toml
treefmt

# This will format:
# - HTML templates with djlint
# - SCSS/SASS with prettier
# - Nix files with alejandra
```

### Content Management
```bash
# Check the site
zola check

# Search index is built automatically when build_search_index = true in config.toml
```

## Architecture

### Site Structure
- `config.toml` - Main site configuration (base URL, title, taxonomies, theme settings, menu, socials)
- `content/` - Markdown content files
  - `content/posts/` - Blog posts
  - `content/projects/` - Project pages
  - `content/about.md` - About page
  - `content/_index.md` - Homepage content
- `templates/` - Tera templates (Zola's templating engine)
  - `base.html` - Base template that all pages extend
  - `page.html`, `section.html` - Content templates
  - `partials/` - Reusable template components (header, nav)
  - `macros/` - Template macros for lists, posts, etc.
  - `shortcodes/` - Custom shortcodes (mermaid, note)
- `sass/` - SCSS stylesheets
  - `main.scss` - Main entry point importing all partials
  - `parts/` - Component styles (_code.scss, _header.scss, etc.)
  - `theme/` - Theme-specific styles (dark.scss, light.scss)
- `static/` - Static assets (images, fonts, icons)
- `public/` - Generated site output (git-ignored, created by zola build)

### Theme System
The site uses a modified Apollo theme with:
- Dual theme support (light/dark/auto/toggle) controlled via `config.toml` extra.theme
- Custom fonts (JetBrains Mono) defined in sass/fonts.scss
- Theme-specific color schemes in sass/theme/dark.scss and sass/theme/light.scss
- Theme toggle implementation in templates/partials/nav.html

### Content Front Matter
All content files use TOML front matter (+++). Common fields:
- `title` - Page title
- `date` - Publication date
- `draft` - Boolean for draft status
- `template` - Override default template
- `tags` - Array of tags for taxonomy
- `description` - Meta description

### Key Features
- Search functionality using ElasticLunr (built from content)
- MathJax rendering for mathematical expressions
- Mermaid diagram support via shortcode
- Custom note shortcode for toggleable notes
- Syntax highlighting with Ayu Light theme
- Table of contents (TOC) generation
- RSS/Atom feeds
- Git-based edit links (configured to point to GitHub)

## Deployment

The site auto-deploys via GitHub Actions (.github/workflows/deploy.yml):
- PRs: Build-only validation with drafts included
- Main branch: Build and deploy to gh-pages branch
- Uses shalzz/zola-deploy-action@v0.20.0

## Working with Content

### Creating new blog posts
1. Create a new .md file in `content/posts/`
2. Add front matter with at minimum: title, date
3. Optionally add tags, description, draft status
4. Use shortcodes like `{{ note() }}` or `{{ mermaid() }}` for enhanced content

### Creating new project pages
1. Create a new .md file in `content/projects/`
2. Add project image to the same directory
3. Front matter should include title and description
4. Projects are displayed as cards on the /projects page

### Customizing Templates
- Templates use Tera syntax (similar to Jinja2)
- Macros in templates/macros/macros.html provide reusable components
- Partials in templates/partials/ are included with `{% include %}`
- All templates extend base.html using `{% block main_content %}`

### Styling Changes
- SCSS files use BEM-like naming conventions
- Component-specific styles are in sass/parts/_*.scss
- Theme colors defined in CSS variables in sass/theme/*.scss
- Main entry point imports all partials in sass/main.scss
