#!/bin/bash
# =============================================================================
# Claude Code Buddy Patcher — "If the game won't drop it, mod the loot table."
#
# Patches the companion generation function in cli.js to force a custom build.
# Only works with npm-installed Claude Code (not native binary installs).
#
# REQUIRES: bash 3.2+ (compatible with macOS default bash)
# PLATFORMS: macOS, Linux, Windows (via Git Bash / WSL / MSYS2)
#
# The patch targets a known minified function body. After Claude Code updates,
# the function name or shape may change and the script will need updating.
# This is version-sensitive by design.
# =============================================================================

set -eo pipefail

# --- Defaults ---
SPECIES="dragon"
EYE_NAME="bullseye"
HAT="wizard"
RARITY="legendary"
SHINY="true"
STAT1="CHAOS"
STAT1_VAL=50
STAT2="WISDOM"
STAT2_VAL=50
INSPIRATION_SEED=1337
CUSTOM_PATH=""
COMPANION_NAME=""
COMPANION_PERSONALITY=""
MODE="patch"  # patch | restore | dry-run | show-current | snapshot

# --- Valid values ---
VALID_SPECIES="duck goose blob cat dragon octopus owl penguin turtle snail ghost axolotl capybara cactus robot rabbit mushroom chonk"
VALID_HATS="none crown tophat propeller halo wizard beanie tinyduck"
VALID_RARITIES="common uncommon rare epic legendary"
VALID_STATS="DEBUGGING PATIENCE CHAOS WISDOM SNARK"
VALID_EYES="dot star dead bullseye spiral hollow"

# --- Eye name to actual unicode character ---
eye_to_symbol() {
  case "$1" in
    dot)      printf '\xC2\xB7' ;;
    star)     printf '\xE2\x9C\xA6' ;;
    dead)     printf '\xC3\x97' ;;
    bullseye) printf '\xE2\x97\x89' ;;
    spiral)   printf '@' ;;
    hollow)   printf '\xC2\xB0' ;;
    *)        return 1 ;;
  esac
}

# --- Rarity to stat cap ---
stat_cap_for() {
  case "$1" in
    common)    echo 5 ;;
    uncommon)  echo 15 ;;
    rare)      echo 25 ;;
    epic)      echo 35 ;;
    legendary) echo 50 ;;
  esac
}

# --- The original function pattern (as of 2026-04-05) ---
ORIGINAL='function WE_(q){let K=JE_(q);return{bones:{rarity:K,species:Zk6(q,W54),eye:Zk6(q,D54),hat:K==="common"?"none":Zk6(q,f54),shiny:q()<0.01,stats:XE_(q,K)},inspirationSeed:Math.floor(q()*1e9)}}'

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --species)    SPECIES="$2"; shift 2 ;;
    --eye)        EYE_NAME="$2"; shift 2 ;;
    --hat)        HAT="$2"; shift 2 ;;
    --rarity)     RARITY="$2"; shift 2 ;;
    --shiny)      SHINY="true"; shift ;;
    --no-shiny)   SHINY="false"; shift ;;
    --stat1)      STAT1="$2"; shift 2 ;;
    --stat1-val)  STAT1_VAL="$2"; shift 2 ;;
    --stat2)      STAT2="$2"; shift 2 ;;
    --stat2-val)  STAT2_VAL="$2"; shift 2 ;;
    --seed)       INSPIRATION_SEED="$2"; shift 2 ;;
    --name)       COMPANION_NAME="$2"; shift 2 ;;
    --personality) COMPANION_PERSONALITY="$2"; shift 2 ;;
    --path)       CUSTOM_PATH="$2"; shift 2 ;;
    --restore)    MODE="restore"; shift ;;
    --dry-run)    MODE="dry-run"; shift ;;
    --show-current) MODE="show-current"; shift ;;
    --show-original) MODE="show-original"; shift ;;
    --snapshot)   MODE="snapshot"; shift ;;
    --help|-h)
      cat <<'HELP'
=====================================
 Claude Code Buddy Patcher
=====================================

Usage: buddy_patch.sh [OPTIONS]

Companion Options:
  --species NAME       duck goose blob cat dragon octopus owl penguin
                       turtle snail ghost axolotl capybara cactus robot
                       rabbit mushroom chonk           (default: dragon)
  --eye NAME           dot star dead bullseye spiral hollow
                                                       (default: bullseye)
  --hat NAME           none crown tophat propeller halo wizard beanie
                       tinyduck                        (default: wizard)
  --rarity NAME        common uncommon rare epic legendary
                                                       (default: legendary)
  --shiny              Enable shiny effect             (default: enabled)
  --no-shiny           Disable shiny effect

Stat Options:
  --stat1 NAME         First boosted stat              (default: CHAOS)
  --stat1-val N        First stat value, integer       (default: 50)
  --stat2 NAME         Second boosted stat             (default: WISDOM)
  --stat2-val N        Second stat value, integer      (default: 50)
                       Valid stats: DEBUGGING PATIENCE CHAOS WISDOM SNARK
                       Natural caps: common=5 uncommon=15 rare=25 epic=35 legendary=50
                       Non-boosted stats default to 1.

Name & Personality (optional):
  --name TEXT          Force a custom name (max 14 chars)
                       If omitted, Claude generates one at first hatch (cached).
  --personality TEXT   Force a custom personality (one sentence)
                       If omitted, Claude generates one at first hatch (cached).
                       These override the AI-generated name/personality.
                       Without them, only the visual traits are locked;
                       name and personality are left to Claude.

Other Options:
  --seed N             Inspiration seed, integer       (default: 1337)
  --path PATH          Custom path to cli.js (auto-detected if omitted)
  --dry-run            Preview build and resolved path without writing
  --show-current       Show detected cli.js path and current patch state
  --show-original      Show the original companion before patching
  --snapshot           Create a timestamped snapshot of current cli.js
  --restore            Restore cli.js from original backup
  --help, -h           Show this help

Examples:
  buddy_patch.sh --show-current
  buddy_patch.sh --dry-run --species ghost --eye star --hat halo --rarity epic
  buddy_patch.sh --species dragon --eye bullseye --hat wizard --rarity legendary --shiny
  buddy_patch.sh --species dragon --rarity legendary --name Accomplice --personality "Offers wisdom disguised as chaos, or chaos disguised as wisdom."
  buddy_patch.sh --restore
HELP
      exit 0
      ;;
    *) echo "ERROR: Unknown option: $1. Use --help for usage."; exit 1 ;;
  esac
done

# =============================================================================
# PATH RESOLUTION
# =============================================================================

find_cli_js() {
  # 1. Custom path
  if [[ -n "$CUSTOM_PATH" ]]; then
    if [[ -f "$CUSTOM_PATH" ]]; then
      echo "$CUSTOM_PATH"
      return 0
    else
      echo "ERROR: Custom path not found: $CUSTOM_PATH" >&2
      return 1
    fi
  fi

  # 2. npm root -g
  if command -v npm &>/dev/null; then
    local npm_root
    npm_root="$(npm root -g 2>/dev/null)"
    local candidate="$npm_root/@anthropic-ai/claude-code/cli.js"
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  fi

  # 3. Common nvm paths (macOS/Linux)
  if [[ -d "${HOME}/.nvm/versions" ]]; then
    local nvm_match
    nvm_match=$(find "${HOME}/.nvm/versions" -maxdepth 6 -name "cli.js" -path "*claude-code*" 2>/dev/null | head -1)
    if [[ -n "$nvm_match" ]]; then
      echo "$nvm_match"
      return 0
    fi
  fi

  # 4. Windows nvm/npm paths (Git Bash / MSYS2)
  if [[ -n "${APPDATA:-}" ]]; then
    if [[ -d "$APPDATA/nvm" ]]; then
      local nvm_match
      nvm_match=$(find "$APPDATA/nvm" -maxdepth 6 -name "cli.js" -path "*claude-code*" 2>/dev/null | head -1)
      if [[ -n "$nvm_match" ]]; then
        echo "$nvm_match"
        return 0
      fi
    fi
    local win_candidate="$APPDATA/npm/node_modules/@anthropic-ai/claude-code/cli.js"
    if [[ -f "$win_candidate" ]]; then
      echo "$win_candidate"
      return 0
    fi
  fi

  return 1
}

CLI_JS=$(find_cli_js) || {
  echo "ERROR: Could not locate cli.js for Claude Code."
  echo ""
  echo "Possible reasons:"
  echo "  - Claude Code installed natively (binary), not via npm"
  echo "    Check: file \$(which claude)"
  echo "  - Claude Code is not installed"
  echo "  - Non-standard install location"
  echo ""
  echo "Use --path /full/path/to/cli.js to specify manually."
  exit 1
}

# Sanity check: is it actually JavaScript?
if file "$CLI_JS" 2>/dev/null | grep -qE "ELF|Mach-O|PE32" && ! file "$CLI_JS" 2>/dev/null | grep -q "text"; then
  echo "ERROR: $CLI_JS appears to be a compiled binary, not JavaScript."
  echo "This patcher only works with npm-installed Claude Code."
  exit 1
fi

BACKUP_FILE="$CLI_JS.original.bak"

# =============================================================================
# DETECT CURRENT STATE
# =============================================================================

detect_state() {
  if grep -qF "$ORIGINAL" "$CLI_JS" 2>/dev/null; then
    echo "original"
  elif grep -q 'function WE_(q){return{bones:{rarity:' "$CLI_JS" 2>/dev/null; then
    echo "patched"
  else
    echo "unknown"
  fi
}

extract_current_build() {
  node -e "
const fs = require('fs');
const eyeLookup = {
  '\u00B7':['dot','\u00B7'],'\u2726':['star','\u2726'],'\u00D7':['dead','\u00D7'],
  '\u25C9':['bullseye','\u25C9'],'@':['spiral','@'],'\u00B0':['hollow','\u00B0'],
  '00B7':['dot','\u00B7'],'2726':['star','\u2726'],'00D7':['dead','\u00D7'],
  '25C9':['bullseye','\u25C9'],'B7':['dot','\u00B7'],'D7':['dead','\u00D7'],
  'B0':['hollow','\u00B0'],'00B0':['hollow','\u00B0']
};
const content = fs.readFileSync('$CLI_JS','utf8');
const m = content.match(/function WE_\(q\)\{return\{bones:\{(.*?)\}/);
if (!m) { console.log('  Could not extract current build details.'); process.exit(0); }
const bones = m[1];
['species','rarity','hat'].forEach(f => {
  const fm = bones.match(new RegExp(f+':\"([^\"]+)\"'));
  if (fm) console.log('  '+f.charAt(0).toUpperCase()+f.slice(1).padEnd(9)+' '+fm[1]);
});
const em = bones.match(/eye:\"([^\"]+)\"/);
if (em) {
  const e = eyeLookup[em[1]] || ['?',em[1]];
  console.log('  Eye        '+e[1]+' ('+e[0]+')');
}
const sm = bones.match(/shiny:(true|false)/);
if (sm) console.log('  Shiny      '+sm[1]);
try {
  const state = JSON.parse(fs.readFileSync(require('os').homedir()+'/.claude.json','utf8'));
  const c = state.companion || {};
  if (c.name) console.log('  Name       '+c.name);
  if (c.personality) console.log('  Personality '+c.personality);
} catch(e) {}
" 2>/dev/null || echo "  Could not extract current build details."
}

# =============================================================================
# MODE: --show-current
# =============================================================================

if [[ "$MODE" == "show-current" ]]; then
  STATE=$(detect_state)
  echo "Path:    $CLI_JS"
  echo "Size:    $(du -h "$CLI_JS" | cut -f1)"
  echo "State:   $STATE"
  if [[ -f "$BACKUP_FILE" ]]; then
    echo "Backup:  $BACKUP_FILE (exists)"
  else
    echo "Backup:  none"
  fi
  if [[ "$STATE" == "patched" ]]; then
    echo ""
    echo "Current build:"
    extract_current_build
  fi
  exit 0
fi

# =============================================================================
# MODE: --show-original
# =============================================================================

if [[ "$MODE" == "show-original" ]]; then
  COMPANION_CACHE_BAK="$HOME/.claude/.companion.original.bak.json"
  echo "=== Original Companion ==="
  echo ""
  # Name & personality from companion cache backup
  if [[ -f "$COMPANION_CACHE_BAK" ]]; then
    node -e "
const data = JSON.parse(require('fs').readFileSync('$COMPANION_CACHE_BAK','utf8'));
if (data.name) console.log('  Name:        '+data.name);
if (data.personality) console.log('  Personality: '+data.personality);
" 2>/dev/null || echo "  Could not read companion cache backup."
  else
    echo "  No companion cache backup found ($COMPANION_CACHE_BAK)"
  fi
  # Traits from cli.js backup
  if [[ -f "$BACKUP_FILE" ]]; then
    if grep -q "inspirationSeed" "$BACKUP_FILE" 2>/dev/null; then
      echo "  (Traits were procedurally generated from your user ID)"
    else
      echo "  Could not read original generation function."
    fi
  else
    echo "  No cli.js backup found ($BACKUP_FILE)"
  fi
  exit 0
fi

# =============================================================================
# MODE: --snapshot
# =============================================================================

if [[ "$MODE" == "snapshot" ]]; then
  SNAP_FILE="$CLI_JS.snapshot.$(date +%Y%m%d-%H%M%S)"
  cp "$CLI_JS" "$SNAP_FILE"
  echo "Snapshot created: $SNAP_FILE"
  exit 0
fi

# =============================================================================
# MODE: --restore
# =============================================================================

if [[ "$MODE" == "restore" ]]; then
  if [[ -f "$BACKUP_FILE" ]]; then
    cp "$BACKUP_FILE" "$CLI_JS"
    echo "Restored cli.js from: $BACKUP_FILE"
  else
    echo "ERROR: No original cli.js backup found at $BACKUP_FILE"
    echo "Reinstall with: npm install -g @anthropic-ai/claude-code"
  fi
  # Restore companion cache if backup exists
  COMPANION_CACHE_BAK="$HOME/.claude/.companion.original.bak.json"
  CLAUDE_STATE="$HOME/.claude.json"
  if [[ -f "$COMPANION_CACHE_BAK" ]] && [[ -f "$CLAUDE_STATE" ]]; then
    node -e "
const fs = require('fs');
const state = JSON.parse(fs.readFileSync('$CLAUDE_STATE','utf8'));
state.companion = JSON.parse(fs.readFileSync('$COMPANION_CACHE_BAK','utf8'));
fs.writeFileSync('$CLAUDE_STATE', JSON.stringify(state, null, 2));
" 2>/dev/null && echo "Restored companion cache from: $COMPANION_CACHE_BAK" || echo "WARNING: Could not restore companion cache"
  fi
  echo "Restart Claude Code for changes to take effect."
  exit 0
fi

# =============================================================================
# VALIDATION (for patch and dry-run modes)
# =============================================================================

# Resolve eye symbol
EYE_SYMBOL=$(eye_to_symbol "$EYE_NAME") || {
  echo "ERROR: Invalid eye '$EYE_NAME'."
  echo "Valid: $VALID_EYES"
  exit 1
}

# Validate enums
validate() {
  local value="$1" name="$2" valid="$3"
  if ! echo "$valid" | grep -qw "$value"; then
    echo "ERROR: Invalid $name '$value'."
    echo "Valid: $valid"
    exit 1
  fi
}

validate "$SPECIES" "species" "$VALID_SPECIES"
validate "$HAT" "hat" "$VALID_HATS"
validate "$RARITY" "rarity" "$VALID_RARITIES"
validate "$STAT1" "stat1" "$VALID_STATS"
validate "$STAT2" "stat2" "$VALID_STATS"

# Validate numeric inputs
validate_integer() {
  local value="$1" name="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $name must be a positive integer, got '$value'."
    exit 1
  fi
}

validate_integer "$STAT1_VAL" "--stat1-val"
validate_integer "$STAT2_VAL" "--stat2-val"
validate_integer "$INSPIRATION_SEED" "--seed"

# Validate name length if provided
if [[ -n "$COMPANION_NAME" ]] && [[ ${#COMPANION_NAME} -gt 14 ]]; then
  echo "ERROR: --name must be 14 characters or fewer, got ${#COMPANION_NAME} ('$COMPANION_NAME')."
  exit 1
fi

# Stat cap warning
STAT_CAP=$(stat_cap_for "$RARITY")
if [[ "$STAT1_VAL" -gt "$STAT_CAP" ]] || [[ "$STAT2_VAL" -gt "$STAT_CAP" ]]; then
  echo "WARNING: Stat values exceed natural cap ($STAT_CAP) for $RARITY rarity."
  echo "         This works but is impossible in normal generation."
  echo ""
fi

# Unique stats
if [[ "$STAT1" == "$STAT2" ]]; then
  echo "ERROR: stat1 and stat2 must be different."
  exit 1
fi

# --- Build stats JSON ---
ALL_STATS=("DEBUGGING" "PATIENCE" "CHAOS" "WISDOM" "SNARK")
STATS_JSON=""
for s in "${ALL_STATS[@]}"; do
  if [[ "$s" == "$STAT1" ]]; then
    val="$STAT1_VAL"
  elif [[ "$s" == "$STAT2" ]]; then
    val="$STAT2_VAL"
  else
    val=1
  fi
  if [[ -n "$STATS_JSON" ]]; then
    STATS_JSON="$STATS_JSON,$s:$val"
  else
    STATS_JSON="$s:$val"
  fi
done

# --- Build replacement ---
REPLACEMENT="function WE_(q){return{bones:{rarity:\"${RARITY}\",species:\"${SPECIES}\",eye:\"${EYE_SYMBOL}\",hat:\"${HAT}\",shiny:${SHINY},stats:{${STATS_JSON}}},inspirationSeed:${INSPIRATION_SEED}}}"

# =============================================================================
# MODE: --dry-run
# =============================================================================

if [[ "$MODE" == "dry-run" ]]; then
  STATE=$(detect_state)
  echo "=== DRY RUN (no changes will be made) ==="
  echo ""
  echo "Path:      $CLI_JS"
  echo "State:     $STATE"
  echo "Backup:    $(if [[ -f "$BACKUP_FILE" ]]; then echo "exists"; else echo "will be created"; fi)"
  echo ""
  echo "Requested build:"
  echo "  Species:  $SPECIES"
  echo "  Eyes:     $EYE_NAME ($EYE_SYMBOL)"
  echo "  Hat:      $HAT"
  echo "  Rarity:   $RARITY"
  echo "  Shiny:    $SHINY"
  echo "  Stat 1:   $STAT1 = $STAT1_VAL"
  echo "  Stat 2:   $STAT2 = $STAT2_VAL"
  echo "  Others:   1 (base)"
  echo "  Seed:     $INSPIRATION_SEED"
  if [[ -n "$COMPANION_NAME" ]]; then
    echo "  Name:     $COMPANION_NAME (forced)"
  else
    echo "  Name:     (AI-generated at first hatch, then cached)"
  fi
  if [[ -n "$COMPANION_PERSONALITY" ]]; then
    echo "  Personality: $COMPANION_PERSONALITY (forced)"
  else
    echo "  Personality: (AI-generated at first hatch, then cached)"
  fi
  echo ""
  if [[ "$STATE" == "original" ]]; then
    echo "Action: will patch directly."
  elif [[ "$STATE" == "patched" ]]; then
    if [[ -f "$BACKUP_FILE" ]]; then
      echo "Action: will restore original first, then re-patch."
    else
      echo "Action: BLOCKED. Already patched and no original backup exists."
      echo "        Reinstall Claude Code first: npm install -g @anthropic-ai/claude-code"
    fi
  else
    echo "Action: BLOCKED. Could not identify current function pattern."
    echo "        Claude Code may have been updated. See --help."
  fi
  exit 0
fi

# =============================================================================
# MODE: patch
# =============================================================================

STATE=$(detect_state)
echo "Path:    $CLI_JS"
echo "State:   $STATE"

# Ensure we have the original function to patch
if [[ "$STATE" == "patched" ]]; then
  if [[ -f "$BACKUP_FILE" ]]; then
    echo "Already patched. Restoring original before re-patching..."
    cp "$BACKUP_FILE" "$CLI_JS"
  else
    echo "ERROR: Already patched and no original backup exists."
    echo "Reinstall Claude Code: npm install -g @anthropic-ai/claude-code"
    exit 1
  fi
elif [[ "$STATE" == "unknown" ]]; then
  echo "ERROR: Could not find the expected generation function in cli.js."
  echo ""
  echo "This likely means Claude Code was updated and minified names changed."
  echo "Search hints to find the new function name:"
  echo "  grep -oP 'function [a-zA-Z_]+\\(q\\)\\{.*inspirationSeed[^}]*\\}\\}' \"$CLI_JS\" | head -3"
  echo "  grep -o 'friend-2026[^\"]*' \"$CLI_JS\""
  echo ""
  echo "Then update the ORIGINAL variable in this script."
  exit 1
fi

# Create immutable original backup (once, never overwritten)
if [[ ! -f "$BACKUP_FILE" ]]; then
  cp "$CLI_JS" "$BACKUP_FILE"
  echo "Original backup created: $BACKUP_FILE"
else
  echo "Original backup exists: $BACKUP_FILE (preserved)"
fi

# Preview
echo ""
echo "Applying build:"
echo "  Species:  $SPECIES"
echo "  Eyes:     $EYE_NAME ($EYE_SYMBOL)"
echo "  Hat:      $HAT"
echo "  Rarity:   $RARITY"
echo "  Shiny:    $SHINY"
echo "  Stat 1:   $STAT1 = $STAT1_VAL"
echo "  Stat 2:   $STAT2 = $STAT2_VAL"
echo "  Others:   1 (base)"
echo "  Seed:     $INSPIRATION_SEED"
if [[ -n "$COMPANION_NAME" ]]; then
  echo "  Name:     $COMPANION_NAME (forced)"
else
  echo "  Name:     (AI-generated at first hatch, then cached)"
fi
if [[ -n "$COMPANION_PERSONALITY" ]]; then
  echo "  Personality: $COMPANION_PERSONALITY (forced)"
else
  echo "  Personality: (AI-generated at first hatch, then cached)"
fi
echo ""

# Apply WE_ patch (visual traits)
perl -i -pe "s/\Q${ORIGINAL}\E/${REPLACEMENT}/" "$CLI_JS"

# Apply EdK patch (name & personality) — only if BOTH are set.
# This is a safety net for fresh hatches (cache cleared / new install).
# The primary mechanism is the ~/.claude.json cache update below.
if [[ -n "$COMPANION_NAME" ]] && [[ -n "$COMPANION_PERSONALITY" ]]; then
  ESCAPED_NAME=$(echo "$COMPANION_NAME" | sed 's/"/\\"/g')
  ESCAPED_PERS=$(echo "$COMPANION_PERSONALITY" | sed 's/"/\\"/g')
  perl -i -0pe "s/async function EdK\(q,K,_\)\{let z=UIY\(K,4\).*?return\{name:ydK\[K%ydK\.length\],personality:\x60A \\\$\{q\.rarity\} \\\$\{q\.species\} of few words\.\x60\}\}/async function EdK(q,K,_){return{name:\"${ESCAPED_NAME}\",personality:\"${ESCAPED_PERS}\"}}/s" "$CLI_JS" 2>/dev/null || true
fi

# Update the persistent companion cache in ~/.claude.json
# The companion is generated once at first hatch and cached here.
# Without updating this file, the old name/personality persists.
CLAUDE_STATE="$HOME/.claude.json"
COMPANION_CACHE_BAK="$HOME/.claude/.companion.original.bak.json"
if [[ -f "$CLAUDE_STATE" ]]; then
  if [[ -n "$COMPANION_NAME" ]] || [[ -n "$COMPANION_PERSONALITY" ]]; then
    node -e "
const fs = require('fs');
const state = JSON.parse(fs.readFileSync('$CLAUDE_STATE','utf8'));
// Backup original companion entry (once, never overwritten)
const bakPath = '$COMPANION_CACHE_BAK';
if (!fs.existsSync(bakPath) && state.companion) {
  fs.writeFileSync(bakPath, JSON.stringify(state.companion, null, 2));
}
if (!state.companion) state.companion = {};
const name = '$COMPANION_NAME';
const pers = \`$COMPANION_PERSONALITY\`;
if (name) state.companion.name = name;
if (pers) state.companion.personality = pers;
fs.writeFileSync('$CLAUDE_STATE', JSON.stringify(state, null, 2));
" 2>/dev/null && echo "Updated companion cache in $CLAUDE_STATE" || echo "WARNING: Could not update $CLAUDE_STATE (name/personality may not apply until cache is cleared)"
    if [[ -f "$COMPANION_CACHE_BAK" ]]; then
      echo "Companion cache backup: $COMPANION_CACHE_BAK (preserved)"
    fi
  fi
else
  if [[ -n "$COMPANION_NAME" ]] || [[ -n "$COMPANION_PERSONALITY" ]]; then
    echo "WARNING: $CLAUDE_STATE not found. Name/personality will apply on next fresh hatch."
  fi
fi

# =============================================================================
# VERIFICATION
# =============================================================================

VERIFY_OK=true

verify_field() {
  local label="$1" pattern="$2"
  if grep -q "$pattern" "$CLI_JS" 2>/dev/null; then
    echo "  [OK] $label"
  else
    echo "  [FAIL] $label"
    VERIFY_OK=false
  fi
}

echo "Verifying patch..."
verify_field "species"  "species:\"${SPECIES}\""
verify_field "rarity"   "rarity:\"${RARITY}\""
verify_field "hat"      "hat:\"${HAT}\""
verify_field "shiny"    "shiny:${SHINY}"
verify_field "stat1"    "${STAT1}:${STAT1_VAL}"
verify_field "stat2"    "${STAT2}:${STAT2_VAL}"
if [[ -n "$COMPANION_NAME" ]]; then
  verify_field "name"   "name:\"${COMPANION_NAME}\""
fi
if [[ -n "$COMPANION_PERSONALITY" ]]; then
  verify_field "personality" "personality:\"$(echo "$COMPANION_PERSONALITY" | head -c 30)"
fi

# JS syntax check if node is available
if command -v node &>/dev/null; then
  if node --check "$CLI_JS" 2>/dev/null; then
    echo "  [OK] JS syntax valid"
  else
    echo "  [FAIL] JS syntax check failed"
    VERIFY_OK=false
  fi
fi

echo ""

if [[ "$VERIFY_OK" == "true" ]]; then
  echo "PATCH APPLIED SUCCESSFULLY. Your companion has been reforged."
  echo "Restart Claude Code for changes to take effect."
  echo "To restore: $0 --restore"
else
  echo "PATCH VERIFICATION FAILED. Restoring original..."
  cp "$BACKUP_FILE" "$CLI_JS"
  echo "Restored. cli.js is unchanged."
  exit 1
fi
