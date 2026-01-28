# Three-Layer Memory System for Moltbot

A self-maintaining knowledge graph that compounds over time.

## Quick Start

```bash
git clone https://github.com/eyeseethru/clawdbot-three-layer-memory.git
cd clawdbot-three-layer-memory
./setup.sh
```

## Overview

Most AI assistants forget by default. Moltbot doesn't — but out of the box, its memory is static. This system upgrades Moltbot into a living knowledge graph.

## Features

- Automatic fact extraction from conversations
- Entity-based knowledge storage
- Weekly summary synthesis
- History preserved (no deletion, only superseding)
- Local models (qwen3:4b + nomic-embed-text)
- Zero cost to run

## Requirements

- Moltbot installed
- Ollama with qwen3:4b
- nomic-embed-text model
- SQLite3

## Setup

See [SETUP.md](SETUP.md) for complete installation instructions.

## License

MIT
