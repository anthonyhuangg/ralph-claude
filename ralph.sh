#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop using Claude Code
# Usage: ./ralph.sh [max_iterations]

set -e

# Colors for terminal output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Display progress tracker
show_progress() {
  if [ ! -f "$PRD_FILE" ]; then
    return
  fi

  local total=$(jq '.userStories | length' "$PRD_FILE" 2>/dev/null || echo 0)
  local passed=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null || echo 0)
  local remaining=$((total - passed))

  echo ""
  echo -e "${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}│                    PROGRESS TRACKER                         │${NC}"
  echo -e "${BOLD}├─────────────────────────────────────────────────────────────┤${NC}"

  # Progress bar
  local bar_width=40
  local filled=$((passed * bar_width / total))
  local empty=$((bar_width - filled))
  local bar=$(printf "%${filled}s" | tr ' ' '█')$(printf "%${empty}s" | tr ' ' '░')
  local percent=$((passed * 100 / total))

  echo -e "${BOLD}│${NC} Progress: ${GREEN}${bar}${NC} ${percent}%"
  echo -e "${BOLD}│${NC} Stories:  ${GREEN}${passed} passed${NC} / ${YELLOW}${remaining} remaining${NC} / ${total} total"
  echo -e "${BOLD}├─────────────────────────────────────────────────────────────┤${NC}"

  # List stories with status
  jq -r '.userStories[] | "\(.id)|\(.title)|\(.passes)"' "$PRD_FILE" 2>/dev/null | while IFS='|' read -r id title passes; do
    if [ "$passes" = "true" ]; then
      echo -e "${BOLD}│${NC} ${GREEN}✓${NC} ${id}: ${title:0:50}"
    else
      echo -e "${BOLD}│${NC} ${RED}○${NC} ${id}: ${title:0:50}"
    fi
  done

  echo -e "${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
  echo ""
}

# Parse arguments
MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo -e "${BOLD}Starting Ralph - Max iterations: $MAX_ITERATIONS${NC}"
show_progress

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo -e "${BLUE}===============================================================${NC}"
  echo -e "${BLUE}  Ralph Iteration $i of $MAX_ITERATIONS${NC}"
  echo -e "${BLUE}===============================================================${NC}"

  # Run Claude Code with the ralph prompt
  # --dangerously-skip-permissions for autonomous operation, --print for output
  OUTPUT=$(claude --dangerously-skip-permissions --print < "$SCRIPT_DIR/CLAUDE.md" 2>&1 | tee /dev/stderr) || true
  
  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    show_progress
    echo ""
    echo -e "${GREEN}${BOLD}✓ Ralph completed all tasks!${NC}"
    echo -e "Completed at iteration $i of $MAX_ITERATIONS"
    exit 0
  fi

  show_progress
  echo -e "${YELLOW}Iteration $i complete. Continuing...${NC}"
  sleep 2
done

show_progress
echo ""
echo -e "${RED}${BOLD}✗ Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks.${NC}"
echo "Check $PROGRESS_FILE for status."
exit 1
