#!/usr/bin/env bash
set -euo pipefail

AQUA=$'\033[96m'
ORANGE=$'\033[33m'
PURPLE=$'\033[35m'
CYAN=$'\033[36m'
BLUE=$'\033[94m'
YELLOW=$'\033[93m'
DIM=$'\033[2m'
RED=$'\033[31m'
RESET=$'\033[0m'
MODEL="${CLAUDE_MODEL:-claude-sonnet-4-20250514}"
RESULT_LIMIT="${RESULT_LIMIT:-300}"
FILE_LINES="${FILE_LINES:-5}"
INDENT="   "

HIDE_TOOLS="Write|TodoWrite|Read|Glob|Grep|Bash|Task"
CURRENT_TOOL=""

process_json() {
  local line="$1"

  local type
  type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || return

  case "$type" in
    system)
      local subtype session_id cwd
      subtype=$(echo "$line" | jq -r '.subtype // empty')
      if [[ "$subtype" == "init" ]]; then
        session_id=$(echo "$line" | jq -r '.session_id')
        cwd=$(echo "$line" | jq -r '.cwd | gsub("/"; "-") | gsub("_"; "-")')
        model_name=$(echo "$line" | jq -r '.model | split("-") | .[1] // .model')
        echo -e "${DIM}[session]"
        echo -e "${INDENT}id:    ${session_id}"
        echo -e "${INDENT}path:  ~/.claude/projects/${cwd}/${session_id}.jsonl"
        echo -e "${INDENT}model: ${model_name}${RESET}"
        echo ""
      fi
      ;;

    stream_event)
      local event_type
      event_type=$(echo "$line" | jq -r '.event.type // empty')

      case "$event_type" in
        content_block_start)
          local block_type name
          block_type=$(echo "$line" | jq -r '.event.content_block.type // empty')
          if [[ "$block_type" == "tool_use" ]]; then
            name=$(echo "$line" | jq -r '.event.content_block.name')
            CURRENT_TOOL="$name"
            case "$name" in
              Edit|MultiEdit) echo -ne "\n${ORANGE}[${name}] " ;;
              Write|TodoWrite|Read|Glob|Grep|Bash|Task) ;; # hide, handled in assistant
              *) echo -ne "\n${PURPLE}[${name}] " ;;
            esac
          fi
          ;;
        content_block_delta)
          local delta_type
          delta_type=$(echo "$line" | jq -r '.event.delta.type // empty')
          case "$delta_type" in
            text_delta)
              echo -n "$(echo "$line" | jq -rj '.event.delta.text // empty')"
              ;;
            input_json_delta)
              if [[ ! "$CURRENT_TOOL" =~ ^($HIDE_TOOLS)$ ]]; then
                echo -n "$(echo "$line" | jq -rj '.event.delta.partial_json // empty')"
              fi
              ;;
          esac
          ;;
        content_block_stop)
          if [[ ! "$CURRENT_TOOL" =~ ^($HIDE_TOOLS)$ ]]; then
            echo -e "${RESET}"
          fi
          CURRENT_TOOL=""
          ;;
        error)
          echo -e "\n${RED}[error] $(echo "$line" | jq -r '.event.error // .event | tostring')${RESET}"
          ;;
      esac
      ;;

    user)
      local content_type
      content_type=$(echo "$line" | jq -r '.message.content[0].type // empty')
      if [[ "$content_type" == "tool_result" ]]; then
        local has_file content
        has_file=$(echo "$line" | jq -r 'if .tool_use_result | type == "object" then .tool_use_result.file // empty else empty end' 2>/dev/null)
        if [[ -n "$has_file" && "$has_file" != "null" ]]; then
          local preview num_lines
          num_lines=$(echo "$line" | jq -r '.tool_use_result.file.numLines // 0')
          preview=$(echo "$line" | jq -r --argjson n "$FILE_LINES" '.tool_use_result.file.content | split("\n") | .[0:$n] | map("'"$INDENT"'" + .) | join("\n")')
          echo -e "${DIM}${INDENT}(${num_lines} lines)"
          echo -e "${preview}"
          [[ "${num_lines:-0}" =~ ^[0-9]+$ && $num_lines -gt $FILE_LINES ]] && echo -e "${INDENT}..."
          echo -e "${RESET}"
        else
          content=$(echo "$line" | jq -r '.message.content[0].content // "no content"')
          if [[ "$content" =~ ^(Todos\ have\ been|The\ file.*has\ been) ]]; then
            : # hide
          elif [[ "$content" =~ \<tool_use_error\> ]]; then
            local error_msg
            error_msg=$(echo "$content" | sed 's/<[^>]*>//g')
            echo -e "${RED}${INDENT}✗ ${error_msg}${RESET}\n"
          elif echo "$content" | jq -e 'type == "array"' &>/dev/null; then
            local parsed
            parsed=$(echo "$content" | jq -r 'map(select(.type? == "text") | .text) | first // "" | gsub("<usage>[^<]*</usage>"; "") | gsub("\n"; " ")')
            echo -e "${DIM}${INDENT}→ ${parsed:0:$RESULT_LIMIT}${RESET}\n"
          elif [[ "$content" == *$'\n'* ]]; then
            echo "$content" 2>/dev/null | head -10 | while IFS= read -r l; do
              echo -e "${DIM}${INDENT}→ ${l}${RESET}"
            done
            [[ $(echo "$content" 2>/dev/null | wc -l) -gt 10 ]] && echo -e "${INDENT}..."
            echo ""
          else
            echo -e "${DIM}${INDENT}→ ${content:0:$RESULT_LIMIT}${RESET}\n"
          fi
        fi
      fi
      ;;

    assistant)
      # Handle TodoWrite
      if echo "$line" | jq -e '.message.content[]? | select(.type == "tool_use" and .name == "TodoWrite")' &>/dev/null; then
        echo -e "\n${YELLOW}[Todo]${RESET}"
        echo "$line" | jq -r --arg g "$AQUA" --arg o "$ORANGE" --arg d "$DIM" --arg r "$RESET" --arg i "$INDENT" '
          .message.content[] | select(.type == "tool_use" and .name == "TodoWrite") | .input.todos[] |
          $i + (if .status == "completed" then $g + "[x]" elif .status == "in_progress" then $o + "[~]" else $d + "[ ]" end) + $r + " " + .content
        '
        echo ""
      fi
      # Handle Write
      if echo "$line" | jq -e '.message.content[]? | select(.type == "tool_use" and .name == "Write")' &>/dev/null; then
        local file_path
        file_path=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use" and .name == "Write") | .input.file_path')
        echo -e "\n${ORANGE}[Write] ${file_path}${RESET}"
      fi
      # Handle Read
      if echo "$line" | jq -e '.message.content[]? | select(.type == "tool_use" and .name == "Read")' &>/dev/null; then
        local file_path
        file_path=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use" and .name == "Read") | .input.file_path')
        echo -e "\n${AQUA}[Read] ${file_path}${RESET}"
      fi
      # Handle Glob
      if echo "$line" | jq -e '.message.content[]? | select(.type == "tool_use" and .name == "Glob")' &>/dev/null; then
        local pattern
        pattern=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use" and .name == "Glob") | .input.pattern')
        echo -e "\n${PURPLE}[Glob] ${pattern}${RESET}"
      fi
      # Handle Grep
      if echo "$line" | jq -e '.message.content[]? | select(.type == "tool_use" and .name == "Grep")' &>/dev/null; then
        local pattern path
        pattern=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use" and .name == "Grep") | .input.pattern')
        path=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use" and .name == "Grep") | .input.path // empty')
        if [[ -n "$path" ]]; then
          echo -e "\n${PURPLE}[Grep] \"${pattern}\" in ${path##*/}${RESET}"
        else
          echo -e "\n${PURPLE}[Grep] \"${pattern}\"${RESET}"
        fi
      fi
      # Handle Bash
      if echo "$line" | jq -e '.message.content[]? | select(.type == "tool_use" and .name == "Bash")' &>/dev/null; then
        local command
        command=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use" and .name == "Bash") | .input.command')
        echo -e "\n${PURPLE}[Bash] ${command//$'\n'/ }${RESET}"
      fi
      # Handle Task
      if echo "$line" | jq -e '.message.content[]? | select(.type == "tool_use" and .name == "Task")' &>/dev/null; then
        local description prompt model
        description=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use" and .name == "Task") | .input.description // empty')
        prompt=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use" and .name == "Task") | .input.prompt // empty')
        model=$(echo "$line" | jq -r '.message.content[] | select(.type == "tool_use" and .name == "Task") | .input.model // "sonnet"')
        echo -e "\n${BLUE}[Task] ${description} (${model})${RESET}"
        if [[ -n "$prompt" ]]; then
          echo "$prompt" | while IFS= read -r l; do
            echo -e "${DIM}${INDENT}${l}${RESET}"
          done
        fi
      fi
      ;;

    error)
      echo -e "\n${RED}[error] $(echo "$line" | jq -r '.error // "unknown error"')${RESET}"
      ;;

    result)
      local is_error
      is_error=$(echo "$line" | jq -r '.is_error')
      if [[ "$is_error" == "true" ]]; then
        echo -e "\n${RED}[error] $(echo "$line" | jq -r '.result // "unknown error"')${RESET}"
      else
        local duration cost turns input_tokens output_tokens
        duration=$(echo "$line" | jq -r '(.duration_ms / 1000 | tostring | .[0:5])')
        cost=$(echo "$line" | jq -r '(.total_cost_usd | tostring | .[0:6])')
        turns=$(echo "$line" | jq -r '.num_turns // 0')
        input_tokens=$(echo "$line" | jq -r '[.usage.input_tokens, .usage.cache_read_input_tokens, .usage.cache_creation_input_tokens] | add // 0')
        output_tokens=$(echo "$line" | jq -r '.usage.output_tokens // 0')
        echo -e "\n${DIM}[done] ${duration}s, \$${cost}, ${turns} turns, ${input_tokens} in / ${output_tokens} out${RESET}"
      fi
      ;;
  esac
}

total=0
invalid=0
has_result=0
claude_exit=0

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if [[ "$line" == EXIT:* ]]; then
    claude_exit="${line#EXIT:}"
    continue
  fi
  ((total++)) || true
  if ! echo "$line" | jq -e . >/dev/null 2>&1; then
    ((invalid++)) || true
    echo -e "${RED}[parse] invalid json (line $total): ${line:0:80}...${RESET}" >&2
    continue
  fi
  if [[ $(echo "$line" | jq -r '.type // empty') == "result" ]]; then
    has_result=1
  fi
  process_json "$line"
done < <(claude --print --verbose --dangerously-skip-permissions --model "$MODEL" \
  --output-format stream-json --include-partial-messages "$@"; echo "EXIT:$?")

echo "" >&2
echo -e "${DIM}[stats] total=$total invalid=$invalid has_result=$has_result exit=$claude_exit${RESET}" >&2

if [[ "$has_result" != "1" ]]; then
  echo -e "${YELLOW}[warn] no result message - claude may have crashed${RESET}" >&2
fi
if [[ "$invalid" -gt 0 ]]; then
  echo -e "${YELLOW}[warn] $invalid lines with invalid json${RESET}" >&2
fi
