#!/bin/sh
# Stand-in for the Claude Code CLI, for tests only. The Multica daemon runs it as an agent; it answers the version
# probe, reads the task prompt, posts a reply on the issue through the `multica` CLI (exactly as a real agent does,
# using the task token the daemon hands it), and reports success in Claude's stream-json format.
case "${1:-}" in
  --version|-v) echo "2.1.0 (Claude Code)"; exit 0 ;;
esac
IFS= read -r prompt || true
issue=$(printf '%s' "$prompt" | grep -oE 'multica issue (comment (list|add)|get) [0-9a-f-]{36}' | head -1 | grep -oE '[0-9a-f-]{36}$')
if [ -n "$issue" ] && multica issue comment add "$issue" --content "fake-agent: task received" >/tmp/fake-claude.log 2>&1; then
  result="replied on $issue"
else
  result="no reply posted"
fi
printf '%s\n' '{"type":"system","subtype":"init","session_id":"fake-session"}'
printf '{"type":"result","subtype":"success","is_error":false,"session_id":"fake-session","result":"%s"}\n' "$result"
