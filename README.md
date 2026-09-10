# Antigravity Statusline

[![Release](https://img.shields.io/github/v/release/chawannua/antigravity-statusline?color=3282b8&label=version&style=flat-square)](https://github.com/chawannua/antigravity-statusline/releases)
![License](https://img.shields.io/github/license/chawannua/antigravity-statusline?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-blue?style=flat-square)
![Stars](https://img.shields.io/github/stars/chawannua/antigravity-statusline?style=flat-square)

Nordic minimalist statusline for Antigravity.

## Preview

```text
~ chawannua/antigravity-statusline ❯ 
```

## Features

- Minimalist design
- Git status integration
- Fast and responsive

## Quick Install

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/chawannua/antigravity-statusline/main/statusline.ps1" -OutFile "$HOME\statusline.ps1"
. $HOME\statusline.ps1
```

## Configuration

You can customize the prompt by editing the variables in `statusline.ps1`.

## Versioning

This project strictly follows [Semantic Versioning](https://semver.org/) (`Major.Minor.Patch`):

- **Major** (`X.0.0`): Breaking changes (e.g. `BREAKING CHANGE` or `feat!:` or `refactor!:`)
- **Minor** (`0.X.0`): New features (e.g. `feat:` or `feat(...):`)
- **Patch** (`0.0.X`): Bug fixes, refactors, docs, style, etc. (e.g. `fix:`, `refactor:`, `perf:`, `docs:`, `chore:`)
