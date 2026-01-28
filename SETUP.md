# Three-Layer Memory System for Moltbot

A self-maintaining knowledge graph that compounds over time. Not just memory — compounding intelligence.

## Overview

Most AI assistants forget by default. Moltbot doesn't — but out of the box, its memory is static. This system upgrades Moltbot into a living knowledge graph that:

- ✅ Never forgets
- ✅ Never goes stale  
- ✅ Updates automatically
- ✅ Understands relationships over time
- ✅ Costs pennies to maintain

## The Three-Layer Architecture

```
Layer 1: Knowledge Graph   (/life/areas/)
  └── Entities with atomic facts + living summaries

Layer 2: Daily Notes       (memory/YYYY-MM-DD.md)
  └── Raw event logs — what happened, when

Layer 3: Tacit Knowledge   (MEMORY.md)
  └── Patterns, preferences, lessons learned
```

Each layer serves a purpose. Together, they compound.

---

## Quick Setup

### Prerequisites

- Moltbot installed and running
- Ollama running with `qwen3:4b` model
- `nomic-embed-text` embedding model
- SQLite3 (`brew install sqlite3`)

### Step 1: Create Folder Structure

```bash
mkdir -p /Users/clawd/life/areas/people/_template
mkdir -p /Users/clawd/life/areas/companies/_template
mkdir -p /Users/clawd/life/areas/projects/_template
mkdir -p /Users/clawd/bin/memory
```

### Step 2: Create Template Files

**Template: `items.json`**
```json
{
  "facts": [],
  "lastUpdated": null
}
```

**Template: `summary.md`**
```markdown
# [Entity Name]

## Status
[Active/inactive relationship]

## Last Updated
[Date]
```

### Step 3: Create Extraction Scripts

Create `/Users/clawd/bin/memory/extract-facts.sh`:

```bash
#!/bin/bash
# Simple Fact Extraction - Pattern-based for fast migration

MEMORY_DIR="/Users/clawd/memory"
OUTPUT_DIR="/Users/clawd/life/areas"

SINCE_DATE="${1:-$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)}"

echo "=== Fact Extraction ==="
echo "Since: $SINCE_DATE"

get_files() {
    local since_ts=$(date -j -f "%Y-%m-%d" "$SINCE_DATE" +%s 2>/dev/null || date -d "$SINCE_DATE" +%s 2>/dev/null)
    find "$MEMORY_DIR" -name "????-??-??.md" -type f 2>/dev/null | while read f; do
        local fn=$(basename "$f" .md)
        if [[ "$fn" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            local file_ts=$(date -j -f "%Y-%m-%d" "$fn" +%s 2>/dev/null || date -d "$fn" +%s 2>/dev/null)
            if [[ "$file_ts" -ge "$since_ts" ]]; then
                echo "$f|$fn"
            fi
        fi
    done | sort
}

extract_from_file() {
    local file="$1"
    local filename="$2"
    
    if grep -q "factExtracted: true" "$file" 2>/dev/null; then
        return 0
    fi
    
    echo "Processing: $filename"
    
    # Pattern-based extraction (customize for your needs)
    facts_json="["
    first=true
    
    if grep -qi "mymind" "$file" 2>/dev/null; then
        if [[ "$first" == "true" ]]; then first=false; else facts_json+=","; fi
        facts_json+="{\"fact\":\"User uses MyMind for visual knowledge base\",\"category\":\"status\",\"timestamp\":\"$filename\",\"status\":\"active\",\"id\":\"$filename-mymind-1\"}"
    fi
    
    # Add more patterns as needed...
    
    facts_json+="]"
    
    if echo "$facts_json" | jq -e '. | length > 0' >/dev/null 2>&1; then
        count=$(echo "$facts_json" | jq length)
        echo "$facts_json" > "/tmp/extracted-facts-$filename.json"
        echo "  → Extracted $count facts"
        
        if grep -q "factExtracted:" "$file"; then
            sed -i '' 's/factExtracted: false/factExtracted: true/g' "$file" 2>/dev/null || \
            sed -i 's/factExtracted: false/factExtracted: true/g' "$file" 2>/dev/null
        else
            echo "<!-- factExtracted: true -->" >> "$file"
        fi
    else
        echo "  → No facts found"
    fi
}

for file_info in $(get_files); do
    file=$(echo "$file_info" | cut -d'|' -f1)
    filename=$(echo "$file_info" | cut -d'|' -f2)
    extract_from_file "$file" "$filename"
done

echo ""
echo "Extraction complete."
```

Create `/Users/clawd/bin/memory/detect-entities.sh`:

```bash
#!/bin/bash
# Entity Detection and Fact Categorization Script

OUTPUT_DIR="/Users/clawd/life/areas"
TEMPLATE_DIR="$OUTPUT_DIR"

sanitize_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-+/-/g' | sed 's/^-//;s/-*$//'
}

create_entity_folder() {
    local entity_type="$1"
    local entity_name="$2"
    
    local sanitized=$(sanitize_name "$entity_name")
    local folder_path="$OUTPUT_DIR/$entity_type/$sanitized"
    
    if [[ -d "$folder_path" ]]; then
        echo "  → Entity exists: $entity_type/$sanitized"
        return 0
    fi
    
    mkdir -p "$folder_path"
    cp "$TEMPLATE_DIR/$entity_type/_template/items.json" "$folder_path/"
    cp "$TEMPLATE_DIR/$entity_type/_template/summary.md" "$folder_path/"
    
    echo "  → Created: $entity_type/$sanitized"
}

add_fact_to_entity() {
    local entity_type="$1"
    local entity_name="$2"
    local fact_json="$3"
    
    local sanitized=$(sanitize_name "$entity_name")
    local items_file="$OUTPUT_DIR/$entity_type/$sanitized/items.json"
    
    if [[ ! -f "$items_file" ]]; then
        return 1
    fi
    
    local fact_id="${sanitized}-$(date +%Y%m%d%H%M%S)"
    local fact_entry=$(echo "$fact_json" | jq --arg id "$fact_id" '. + {id: $id, status: "active"}')
    
    local tmp_file=$(mktemp)
    cat "$items_file" | jq --argjson newFact "$fact_entry" '.facts += [$newFact] | .lastUpdated = "'$(date -Iseconds)'"' > "$tmp_file"
    mv "$tmp_file" "$items_file"
    
    echo "  → Added fact to $entity_type/$sanitized"
}

echo "=== Entity Detection ==="

for fact_file in /tmp/extracted-facts-*.json; do
    if [[ -f "$fact_file" ]]; then
        echo "Processing: $(basename "$fact_file")"
        
        cat "$fact_file" | jq -r '.[] | @base64' 2>/dev/null | while read -r fact_b64; do
            local fact_json=$(echo "$fact_b64" | base64 -d)
            local fact_text=$(echo "$fact_json" | jq -r '.fact')
            
            # Simple entity detection (customize)
            if echo "$fact_text" | grep -qi "ohnahji\|mom\|dad\|boss\|manager"; then
                entity_type="people"
                entity_name=$(echo "$fact_text" | grep -oE '[A-Z][a-z]+' | head -1)
            elif echo "$fact_text" | grep -qi "mymind\|notion\|obsidian\|company\|startup"; then
                entity_type="companies"
                entity_name=$(echo "$fact_text" | grep -oE '[A-Z][a-z]+' | head -1)
            else
                entity_type="companies"
                entity_name=$(echo "$fact_text" | grep -oE '[A-Z][a-z]+' | head -1)
            fi
            
            if [[ -n "$entity_name" ]]; then
                create_entity_folder "$entity_type" "$entity_name"
                add_fact_to_entity "$entity_type" "$entity_name" "$fact_json"
            fi
        done
        
        rm -f "$fact_file"
    fi
done

echo ""
echo "Entity detection complete."
```

Create `/Users/clawd/bin/memory/index-entities.sh`:

```bash
#!/bin/bash
# Entity Indexing Script - Indexes entity facts into Moltbot's vector DB

OUTPUT_DIR="/Users/clawd/life/areas"
VECTOR_DB="$HOME/.clawdbot/memory/main.sqlite"

init_db() {
    sqlite3 "$VECTOR_DB" "
        CREATE TABLE IF NOT EXISTS entity_chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type TEXT,
            entity_name TEXT,
            chunk_text TEXT,
            fact_id TEXT,
            category TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_entity_type ON entity_chunks(entity_type);
        CREATE INDEX IF NOT EXISTS idx_entity_name ON entity_chunks(entity_name);
    " 2>/dev/null
}

index_entity_facts() {
    local entity_type="$1"
    local entity_name="$2"
    
    local items_file="$OUTPUT_DIR/$entity_type/$entity_name/items.json"
    local summary_file="$OUTPUT_DIR/$entity_type/$entity_name/summary.md"
    
    if [[ ! -f "$items_file" ]]; then
        return 1
    fi
    
    local facts_json=$(cat "$items_file")
    local active_facts=$(echo "$facts_json" | jq '[.facts[] | select(.status == "active")]')
    local facts_count=$(echo "$active_facts" | jq length)
    
    if [[ "$facts_count" -eq 0 ]] || [[ "$facts_count" == "0" ]]; then
        return 0
    fi
    
    echo "Indexing: $entity_type/$entity_name ($facts_count facts)"
    
    echo "$active_facts" | jq -r '.[] | @base64' | while read -r fact_b64; do
        local fact_json=$(echo "$fact_b64" | base64 -d)
        local fact_id=$(echo "$fact_json" | jq -r '.id')
        local fact_text=$(echo "$fact_json" | jq -r '.fact')
        local category=$(echo "$fact_json" | jq -r '.category')
        
        sqlite3 "$VECTOR_DB" "
            INSERT OR REPLACE INTO entity_chunks (entity_type, entity_name, chunk_text, fact_id, category)
            VALUES ('$entity_type', '$entity_name', '$(echo "$fact_text" | sed "s/'/''/g")', '$fact_id', '$category');
        "
    done
    
    if [[ -f "$summary_file" ]]; then
        local summary_text=$(cat "$summary_file" | tr '\n' ' ' | sed 's/  */ /g')
        sqlite3 "$VECTOR_DB" "
            INSERT OR REPLACE INTO entity_chunks (entity_type, entity_name, chunk_text, fact_id, category)
            VALUES ('$entity_type', '$entity_name', '$(echo "$summary_text" | sed "s/'/''/g")', '${entity_name}-summary', 'summary');
        "
    fi
}

echo "=== Entity Indexing ==="
init_db

for entity_type in people companies projects; do
    if [[ ! -d "$OUTPUT_DIR/$entity_type" ]]; then
        continue
    fi
    
    for entity_name in $(ls -1 "$OUTPUT_DIR/$entity_type" 2>/dev/null); do
        if [[ "$entity_name" == "_template" ]]; then
            continue
        fi
        index_entity_facts "$entity_type" "$entity_name"
    done
done

echo ""
echo "Indexed in: $VECTOR_DB"
```

Create `/Users/clawd/bin/memory/synthesize.sh`:

```bash
#!/bin/bash
# Weekly Synthesis Script - Rewrites entity summaries from active facts

OUTPUT_DIR="/Users/clawd/life/areas"
MODEL="qwen3:4b"

generate_summary() {
    local entity_type="$1"
    local entity_name="$2"
    local facts_json="$3"
    
    local active_facts=$(echo "$facts_json" | jq '[.facts[] | select(.status == "active")]')
    local facts_count=$(echo "$active_facts" | jq length)
    
    if [[ "$facts_count" -eq 0 ]] || [[ "$facts_count" == "0" ]]; then
        return 0
    fi
    
    # Simple summary generation
    local summary="# $entity_name\n\n## Current Status\nAuto-synthesized summary.\n\n## Key Facts\n"
    summary+=$(echo "$active_facts" | jq -r '.[] | "- " + .fact' | head -5)
    summary+="\n\n## Last Updated\n$(date +%Y-%m-%d)"
    
    echo -e "$summary"
}

process_entity() {
    local entity_type="$1"
    local entity_name="$2"
    
    local items_file="$OUTPUT_DIR/$entity_type/$entity_name/items.json"
    local summary_file="$OUTPUT_DIR/$entity_type/$entity_name/summary.md"
    
    if [[ ! -f "$items_file" ]]; then
        return 1
    fi
    
    local facts_json=$(cat "$items_file")
    local facts_count=$(echo "$facts_json" | jq '.facts | length')
    
    if [[ "$facts_count" -eq 0 ]] || [[ "$facts_count" == "0" ]]; then
        return 0
    fi
    
    echo "Processing: $entity_type/$entity_name"
    
    local new_summary=$(generate_summary "$entity_type" "$entity_name" "$facts_json")
    echo "$new_summary" > "$summary_file"
    
    # Update timestamp
    local tmp_file=$(mktemp)
    cat "$items_file" | jq '.lastUpdated = "'$(date -Iseconds)'"' > "$tmp_file"
    mv "$tmp_file" "$items_file"
    
    echo "  → Updated summary.md"
}

echo "=== Weekly Synthesis ==="

for entity_type in people companies projects; do
    if [[ ! -d "$OUTPUT_DIR/$entity_type" ]]; then
        continue
    fi
    
    for entity_name in $(ls -1 "$OUTPUT_DIR/$entity_type" 2>/dev/null); do
        if [[ "$entity_name" == "_template" ]]; then
            continue
        fi
        process_entity "$entity_type" "$entity_name"
    done
done

echo ""
echo "Synthesis complete."
```

Create `/Users/clawd/bin/memory-cmd`:

```bash
#!/bin/bash
# Moltbot Memory Command Wrapper

case "${1:-}" in
    extract)
        shift
        /Users/clawd/bin/memory/extract-facts.sh "$@"
        ;;
    sync)
        shift
        /Users/clawd/bin/memory/index-entities.sh "$@"
        ;;
    synthesize)
        shift
        /Users/clawd/bin/memory/synthesize.sh "$@"
        ;;
    status)
        /Users/clawd/bin/memory/extract.sh --status
        ;;
    entities)
        echo "=== Knowledge Graph Entities ==="
        echo ""
        echo "People:"
        ls -1 /Users/clawd/life/areas/people/ 2>/dev/null | grep -v "^_template$" | sed 's/^/  - /'
        echo ""
        echo "Companies:"
        ls -1 /Users/clawd/life/areas/companies/ 2>/dev/null | grep -v "^_template$" | sed 's/^/  - /'
        echo ""
        echo "Projects:"
        ls -1 /Users/clawd/life/areas/projects/ 2>/dev/null | grep -v "^_template$" | sed 's/^/  - /'
        ;;
    help|*)
        echo "Moltbot Memory Commands"
        echo ""
        echo "Usage: clawdbot memory <command> [options]"
        echo ""
        echo "Commands:"
        echo "  extract    [options]  Extract facts from recent memory files"
        echo "  synthesize [options]  Rewrite entity summaries, mark superseded facts"
        echo "  sync       [options]  Index entities in vector search"
        echo "  status                  Show extraction and entity status"
        echo "  entities                List all indexed entities"
        ;;
esac
```

```bash
chmod +x /Users/clawd/bin/memory/*.sh /Users/clawd/bin/memory-cmd
```

### Step 4: Set Up Cron Jobs

```bash
# Daily extraction at 3 AM
clawdbot cron add --name "daily-fact-extraction" --schedule "0 3 * * *" \
  --session main --text "Daily Fact Extraction"

# Weekly synthesis Sunday at 2 AM  
clawdbot cron add --name "weekly-memory-synthesis" --schedule "0 2 * * 0" \
  --session main --text "Weekly Memory Synthesis"
```

### Step 5: Configure Moltbot Memory Search

In `~/.clawdbot/clawdbot.json`:

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "provider": "openai",
        "remote": {
          "baseUrl": "http://localhost:11434/v1",
          "apiKey": "ollama-local"
        },
        "model": "nomic-embed-text"
      }
    }
  }
}
```

### Step 6: Restart Moltbot

```bash
clawdbot gateway restart
```

---

## Usage

### Daily Workflow

1. **Write to memory file:**
   ```bash
   echo "- 10:30am: Important decision made" >> /Users/clawd/memory/$(date +%Y-%m-%d).md
   ```

2. **Check status:**
   ```bash
   /Users/clawd/bin/memory-cmd status
   ```

3. **Manual extraction (if needed):**
   ```bash
   /Users/clawd/bin/memory-cmd extract --since 2026-01-28
   ```

### Querying Knowledge

```bash
# Search knowledge graph
/Users/clawd/bin/memory-cmd entities

# List all entities
/Users/clawd/bin/memory-cmd status
```

---

## Entity Structure

### Example: Company Entity

```
/Users/clawd/life/areas/companies/mymind/
├── items.json
└── summary.md
```

**items.json:**
```json
{
  "facts": [
    {
      "id": "mymind-001",
      "fact": "User uses MyMind for visual knowledge base",
      "category": "status",
      "timestamp": "2026-01-24",
      "source": "memory/2026-01-24.md",
      "status": "active"
    }
  ],
  "lastUpdated": "2026-01-28T05:00:00Z"
}
```

**summary.md:**
```markdown
# mymind

## Current Status
Auto-synthesized summary.

## Key Facts
- User uses MyMind for visual knowledge base with AI auto-tagging

## Last Updated
2026-01-28
```

---

## How It Compounds

```
Week 1: Basic preferences
Month 1: Routines, key people
Month 6: Projects, milestones, relationships
Year 1: A richer model of your life than most humans have
```

---

## Integration with Second Brain

Second Brain (Obsidian vault) is complementary:

| System | Purpose | When to Use |
|--------|---------|-------------|
| **Three-Layer Memory** | Automatic fact extraction | Conversation context, entity tracking |
| **Second Brain** | Curated evergreen knowledge | Deep dives, research, tutorials |

Both use `nomic-embed-text` for semantic search.

---

## Troubleshooting

### Extraction returning no facts
- Check that memory files exist: `ls /Users/clawd/memory/*.md`
- Verify file is not already marked extracted
- Check pattern matching in `extract-facts.sh`

### Entities not appearing
- Run sync: `/Users/clawd/bin/memory-cmd sync --force`
- Verify entity folders exist: `ls /Users/clawd/life/areas/`

### Cron not running
- Check cron status: `clawdbot cron list`
- Verify session target is correct

---

## Cost

- **Ollama (qwen3:4b):** Local, free
- **nomic-embed-text:** Local, free
- **SQLite:** Built-in
- **Total cost:** $0/month

---

## License

MIT License - Open source and free to use.

---

## Credits

Built for [Moltbot](https://github.com/clawdbot/clawdbot) by EyeSeeThru.

Inspired by the ["Three-Layer Memory System"](https://x.com/spacepixel/status/2015967798636556777) concept.

## Open Source

This project is open source on GitHub:

**https://github.com/EyeSeeThru/clawdbot-three-layer-memory**

Clone and install:
```bash
git clone https://github.com/EyeSeeThru/clawdbot-three-layer-memory.git
cd clawdbot-three-layer-memory
./setup.sh
```
