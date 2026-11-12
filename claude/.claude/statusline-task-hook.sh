#!/usr/bin/env bash
# Records what a Claude Code session is doing, for the task row that
# statusline-command.sh draws above the prompt. Wired in settings.json to
# UserPromptSubmit, PreToolUse, PostToolUse, Notification (permission and
# elicitation prompts only), Stop and SessionEnd.
#
# Per session it keeps four one-line files in $XDG_RUNTIME_DIR/claude-task/:
#   <session>.state     working | waiting | done
#   <session>.prompt    the latest prompt, flattened to one line
#   <session>.label     that prompt as a task label, the outcome wanted in
#                       plain words ("Remove empty strips in the HUD overview")
#   <session>.activity  the step in progress ("edit theme.css", "Run tests")
#
# The label is what the row shows: a prompt like "looks good, but it is still
# wrong" names no task on its own, so each prompt is put to Haiku in the
# background, together with the previous label and the start of the assistant's
# last message, which say what "it" is. Until the answer lands, and whenever
# the call fails, the row falls back to the prompt itself.
#
# Claude Code also submits things the user never typed as prompts: a subagent's
# report, a background task's notification. Those leave prompt and label alone,
# or every hand-back would rename the task after the subagent's findings.
# Separate files, each replaced by a rename, so parallel tool calls cannot
# tear one another's writes.
#
# Prints nothing and always exits 0: a UserPromptSubmit hook's stdout is added
# to the conversation, and a failing hook must never get in the session's way.

# The labelling call below is itself a Claude Code run; it loads no settings
# and so no hooks, and this stops the loop should that ever change.
[[ -n "${CLAUDE_TASK_LABEL:-}" ]] && exit 0

dir="${XDG_RUNTIME_DIR:-/tmp}/claude-task"
input=$(cat)

# One jq call: event, session id and the text to record, split on the unit
# separator (tabs would collapse an empty field). `clean` strips control
# characters, so recorded text can hold neither the separator nor an escape
# sequence the status line would then print.
IFS=$'\x1f' read -r event sid text < <(jq -r '
  def clean: tostring | gsub("[[:cntrl:] ]+"; " ") | gsub("^ | $"; "") | .[0:160];
  def base: tostring | split("/") | last;
  # What the user typed: the prompt without the blocks Claude Code adds.
  def typed: .prompt // "" | gsub("<system-reminder>[\\s\\S]*?</system-reminder>"; "") | gsub("^\\s+"; "");
  [ ( if .hook_event_name == "UserPromptSubmit"
        and (typed | test("^(<agent-message|<task-notification|Another Claude session sent a message|$)"))
      then "AgentMessage" else .hook_event_name // "" end ),
    .session_id // "",
    ( if .hook_event_name == "UserPromptSubmit" then typed
      elif .hook_event_name == "PreToolUse" then
        ( .tool_name // "" ) as $t | ( .tool_input // {} ) as $i
        | if $t == "Bash" then $i.description // $i.command // "shell"
          elif ($t | test("^(Edit|Write|MultiEdit|NotebookEdit)$")) then "edit " + ($i.file_path // $i.notebook_path // "" | base)
          elif $t == "Read" then "read " + ($i.file_path // "" | base)
          elif ($t | test("^(Grep|Glob)$")) then "search " + ($i.pattern // "")
          elif ($t | test("^(Agent|Task)$")) then "agent: " + ($i.description // "")
          elif ($t | test("^Web")) then "web " + ($i.query // $i.url // "")
          elif ($t | startswith("mcp__")) then $t | split("__") | .[1:] | join(" ")
          else $t | ascii_downcase end
      else "" end | clean ) ] | join("\u001f")' <<<"$input" 2>/dev/null)

# The id becomes a file name; anything but a plain token is not ours to write.
[[ "$sid" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

put() {
  printf '%s\n' "$2" >"$dir/$sid.$1.$$" 2>/dev/null && mv -f "$dir/$sid.$1.$$" "$dir/$sid.$1" 2>/dev/null
}

# label_task <previous label>: ask Haiku what the prompt just submitted is
# about and wants changed, and record the answer, unless a newer prompt has
# arrived meanwhile.
label_task() {
  local prev="$1" ask transcript last="" label
  command -v claude >/dev/null || return 0
  ask=$(jq -r '.prompt // "" | gsub("<system-reminder>[\\s\\S]*?</system-reminder>"; "") | gsub("^\\s+"; "") | .[0:2000]' <<<"$input" 2>/dev/null)
  [[ -n "$ask" ]] || return 0
  # The opening of the assistant's last message is its summary of the turn
  # before. Read leniently: the tail of a transcript can start mid-record.
  transcript=$(jq -r '.transcript_path // ""' <<<"$input" 2>/dev/null)
  [[ -r "$transcript" ]] && last=$(tail -n 200 "$transcript" 2>/dev/null | jq -Rrs '
    [ split("\n")[] | fromjson? | select(.type == "assistant" and (.isSidechain | not))
      | .message.content[]? | select(.type == "text") | .text ] | last // "" | .[0:600]' 2>/dev/null)
  # Run from the state dir with every setting source off: no project context,
  # hooks, tools or MCP servers, only the account's login.
  label=$(cd "$dir" && printf 'Previous task label: %s\n\nAssistant'\''s last message (start):\n%s\n\nNewest user message:\n%s\n' \
    "${prev:-none}" "${last:-none}" "$ask" |
    CLAUDE_TASK_LABEL=1 timeout 30 claude -p --model "${CLAUDE_TASK_LABEL_MODEL:-haiku}" --no-session-persistence \
      --tools "" --strict-mcp-config --disable-slash-commands --setting-sources "" \
      --system-prompt "You write the one-line label a status bar shows so its user can tell at a glance what a coding session is working on. You get the previous label, the start of the assistant's last message, and the user's newest message to the assistant. Reply with exactly one plain imperative sentence of 4 to 9 words that states the concrete outcome the user wants, in everyday words for what they would see or get. Examples: 'Remove empty strips in the HUD overview', 'Keep scrolling working in fullscreen scroll mode', 'Make the Obsidian theme easier to read', 'Commit and push the Obsidian theme fixes'. Name the visible feature or part of the product, never file names, function names or other internal identifiers. No category or prefix in front and no colon: never 'Review feedback: ...', 'Fix: ...', 'Bug: ...'. If the newest message is feedback, a correction, a complaint or a pasted review about work in progress, the label is the goal of that work as now corrected, not the fact that feedback arrived; things the user quotes as examples are illustrations, not the task. If it only approves or says to continue, label the step that sets off and say what it applies to. Resolve 'it', 'this' and 'that' from the context, so the label makes sense to someone who sees nothing else. No quotes, no trailing period, nothing before the label, never answer the message itself." \
      2>/dev/null) || return 0
  label=$(tr -d '\000-\037\177' <<<"${label%%$'\n'*}")
  # A label is a handful of words; anything longer is the model talking about
  # the message instead, and the prompt itself serves better than that.
  local words
  read -ra words <<<"$label"
  ((${#words[@]} <= 12)) || return 0
  label="${label:0:72}"
  [[ -n "$label" && "$(cat "$dir/$sid.prompt" 2>/dev/null)" == "$text" ]] && put label "$label"
}

mkdir -p "$dir" 2>/dev/null || exit 0

case "$event" in
UserPromptSubmit)
  prev=$(cat "$dir/$sid.label" 2>/dev/null)
  put prompt "$text"
  rm -f "$dir/$sid.label" 2>/dev/null
  put activity ""
  put state working
  # Detached with every stream closed, so the prompt is not held up by it.
  label_task "$prev" </dev/null >/dev/null 2>&1 &
  disown
  ;;
PreToolUse)
  put activity "$text"
  put state working
  ;;
PostToolUse | AgentMessage)
  # A granted permission prompt leaves no event of its own; the tool
  # finishing is the first sign the session is moving again. A subagent's
  # report likewise only means the session is back at work.
  put state working
  ;;
Notification)
  put state waiting
  ;;
Stop)
  put activity ""
  put state "done"
  ;;
SessionEnd)
  rm -f "$dir/$sid".{state,prompt,label,activity} 2>/dev/null
  ;;
esac
exit 0
