#!/bin/bash
# Three-Layer Memory System Setup Script
# Run this on your Moltbot instance

set -e

CLAWD_PATH="${CLAWD_PATH:-$HOME/clawd}"
MEMORY_PATH="$CLAWD_PATH/life/areas"
BIN_PATH="$CLAWD_PATH/bin/memory"

echo "=== Three-Layer Memory System Setup ==="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v sqlite3 &> /dev/null; then
    echo "Error: sqlite3 not found. Install with: brew install sqlite3"
    exit 1
fi

# Create folder structure
echo "Creating folder structure..."
mkdir -p "$MEMORY_PATH/people/_template"
mkdir -p "$MEMORY_PATH/companies/_template"
mkdir -p "$MEMORY_PATH/projects/_template"
mkdir -p "$BIN_PATH"

# Create template files
echo "Creating templates..."

cat > "$MEMORY_PATH/people/_template/items.json" << 'TEMPLATE'
{
  "facts": [],
  "lastUpdated": null
}
TEMPLATE

cat > "$MEMORY_PATH/people/_template/summary.md" << 'TEMPLATE'
# [Entity Name]

## Status
[Active/inactive relationship]

## Last Updated
[Date]
TEMPLATE

cp "$MEMORY_PATH/people/_template/items.json" "$MEMORY_PATH/companies/_template/"
cp "$MEMORY_PATH/people/_template/summary.md" "$MEMORY_PATH/companies/_template/"
cp "$MEMORY_PATH/people/_template/items.json" "$MEMORY_PATH/projects/_template/"
cp "$MEMORY_PATH/people/_template/summary.md" "$MEMORY_PATH/projects/_template/"

# Copy scripts
echo "Installing scripts..."

# extract-facts.sh
cat > "$BIN_PATH/extract-facts.sh" << 'SCRIPT'
#!/bin/bash
# Simple Fact Extraction - Pattern-based for fast migration

MEMORY_DIR="/Users/estm/clawd/memory"
OUTPUT_DIR="/Users/estm/clawd/life/areas"

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
    
    # Add your pattern-based extraction here
    echo "  → No facts found (customize extract-facts.sh)"
}

for file_info in $(get_files); do
    file=$(echo "$file_info" | cut -d'|' -f1)
    filename=$(echo "$file_info" | cut -d'|' -f2)
    extract_from_file "$file" "$filename"
done

echo ""
echo "Extraction complete."
SCRIPT

# detect-entities.sh
cat > "$BIN_PATH/detect-entities.sh" << 'SCRIPT'
#!/bin/bash
# Entity Detection and Fact Categorization Script

OUTPUT_DIR="/Users/estm/clawd/life/areas"
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
        rm -f "$fact_file"
    fi
done

echo ""
echo "Entity detection complete."
SCRIPT

# index-entities.sh
cat > "$BIN_PATH/index-entities.sh" << 'SCRIPT'
#!/bin/bash
# Entity Indexing Script

OUTPUT_DIR="/Users/estm/clawd/life/areas"
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
    " 2>/dev/null
}

index_entity_facts() {
    local entity_type="$1"
    local entity_name="$2"
    
    local items_file="$OUTPUT_DIR/$entity_type/$entity_name/items.json"
    
    if [[ ! -f "$items_file" ]]; then
        return 1
    fi
    
    echo "Indexing: $entity_type/$entity_name"
}

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
    fi
done

echo ""
echo "Indexed in: $VECTOR_DB"
SCRIPT

# synthesize.sh
cat > "$BIN_PATH/synthesize.sh" << 'SCRIPT'
#!/bin/bash
# Weekly Synthesis Script

OUTPUT_DIR="/Users/estm/clawd/life/areas"

process_entity() {
    local entity_type="$1"
    local entity_name="$2"
    
    local items_file="$OUTPUT_DIR/$entity_type/$entity_name/items.json"
    local summary_file="$OUTPUT_DIR/$entity_type/$entity_name/summary.md"
    
    if [[ ! -f "$items_file" ]]; then
        return 1
    fi
    
    echo "Processing: $entity_type/$entity_name"
    
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
    fi
done

echo ""
echo "Synthesis complete."
SCRIPT

# memory-cmd
cat > "$BIN_PATH/../memory-cmd" << 'SCRIPT'
#!/bin/bash
# Moltbot Memory Command Wrapper

case "${1:-}" in
    extract)
        shift
        /Users/estm/clawd/bin/memory/extract-facts.sh "$@"
        ;;
    sync)
        shift
        /Users/estm/clawd/bin/memory/index-entities.sh "$@"
        ;;
    synthesize)
        shift
        /Users/estm/clawd/bin/memory/synthesize.sh "$@"
        ;;
    status)
        /Users/estm/clawd/bin/memory/extract.sh --status
        ;;
    entities)
        echo "=== Knowledge Graph Entities ==="
        echo ""
        echo "People:"
        ls -1 /Users/estm/clawd/life/areas/people/ 2>/dev/null | grep -v "^_template$" | sed 's/^/  - /'
        echo ""
        echo "Companies:"
        ls -1 /Users/estm/clawd/life/areas/companies/ 2>/dev/null | grep -v "^_template$" | sed 's/^/  - /'
        echo ""
        echo "Projects:"
        ls -1 /Users/estm/clawd/life/areas/projects/ 2>/dev/null | grep -v "^_template$" | sed 's/^/  - /'
        ;;
    help|*)
        echo "Moltbot Memory Commands"
        echo ""
        echo "Usage: clawdbot memory <command> [options]"
        echo ""
        echo "Commands:"
        echo "  extract    Extract facts from recent memory files"
        echo "  synthesize Rewrite entity summaries, mark superseded facts"
        echo "  sync       Index entities in vector search"
        echo "  status     Show extraction and entity status"
        echo "  entities   List all indexed entities"
        ;;
esac
SCRIPT

chmod +x "$BIN_PATH"/*.sh "$BIN_PATH/../memory-cmd"

# Set up cron jobs
echo ""
echo "Setting up cron jobs..."
echo "Run these commands manually:"
echo "  clawdbot cron add --name 'daily-fact-extraction' --schedule '0 3 * * *' --session main"
echo "  clawdbot cron add --name 'weekly-memory-synthesis' --schedule '0 2 * * 0' --session main"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Configure memory search in ~/.clawdbot/clawdbot.json"
echo "2. Restart Moltbot: clawdbot gateway restart"
echo "3. Test: /Users/estm/clawd/bin/memory-cmd status"
echo ""
echo "See SETUP.md for full documentation."
