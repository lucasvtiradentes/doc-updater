#!/usr/bin/env bash
set -euo pipefail

GREEN=$'\033[32m'
ORANGE=$'\033[33m'
PURPLE=$'\033[35m'
RESET=$'\033[0m'
MODEL="${CLAUDE_MODEL:-claude-sonnet-4-20250514}"

claude --print --verbose --dangerously-skip-permissions --model "$MODEL" --output-format stream-json --include-partial-messages "$@" | \
  jq --unbuffered -j --arg green "$GREEN" --arg orange "$ORANGE" --arg purple "$PURPLE" --arg reset "$RESET" '
    if .type == "stream_event" and .event.type == "content_block_delta" and .event.delta.type == "text_delta" then
      .event.delta.text
    elif .type == "stream_event" and .event.type == "content_block_start" and .event.content_block.type == "tool_use" then
      if .event.content_block.name == "Read" then
        "\n" + $green + "[tool] " + .event.content_block.name + " "
      elif (.event.content_block.name == "Edit" or .event.content_block.name == "MultiEdit" or .event.content_block.name == "Write") then
        "\n" + $orange + "[tool] " + .event.content_block.name + " "
      else
        "\n" + $purple + "[tool] " + .event.content_block.name + " "
      end
    elif .type == "stream_event" and .event.type == "content_block_delta" and .event.delta.type == "input_json_delta" then
      .event.delta.partial_json
    elif .type == "stream_event" and .event.type == "content_block_stop" then
      $reset + "\n"
    elif .type == "error" then
      "\n\u001b[31m[error] " + (.error // "unknown error" | tostring) + $reset + "\n"
    elif .type == "stream_event" and .event.type == "error" then
      "\n\u001b[31m[error] " + (.event.error // .event | tostring) + $reset + "\n"
    elif .type == "result" and .is_error == true then
      "\n\u001b[31m[error] " + (.result // "unknown error" | tostring) + $reset + "\n"
    else empty end
  '
