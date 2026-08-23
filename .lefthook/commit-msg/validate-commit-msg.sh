#!/usr/bin/env bash
# .lefthook/commit-msg/validate-commit-msg.sh
# Enforces Conventional Commits format.
# https://www.conventionalcommits.org

MSG_FILE="$1"

# Read first non-comment line
MSG=$(grep -v '^#' "$MSG_FILE" | head -1)

# type(scope)!: description
# - type     required, from allowed list
# - (scope)  optional, lowercase/digits/hyphens
# - !        optional, marks breaking change
# - desc     1–72 chars
TYPES="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
PATTERN="^(${TYPES})(\([a-z0-9_/-]+\))?(!)?: .{1,72}$"

if ! echo "$MSG" | grep -qE "$PATTERN"; then
  echo ""
  echo "❌  Commit message does not follow Conventional Commits."
  echo ""
  echo "   Format:  <type>(<scope>): <description>"
  echo "   Max:     72 chars on the first line"
  echo ""
  echo "   Types:   feat · fix · docs · style · refactor · perf"
  echo "            test · build · ci · chore · revert"
  echo ""
  echo "   Examples:"
  echo "     feat(inbox): add Gmail OAuth integration"
  echo "     fix: handle nil thread_id in email categorizer"
  echo "     chore(deps): bump credo to 1.7.5"
  echo "     feat!: redesign contact timeline (breaking change)"
  echo "     docs: update ICP section in wiki"
  echo ""
  echo "   Your message: \"$MSG\""
  echo ""
  exit 1
fi

exit 0
