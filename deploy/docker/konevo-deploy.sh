#!/usr/bin/env bash
set -Eeuo pipefail

# Run only from the systemd unit in konevo-deploy.service. It polls the public
# GitHub Release API, so it needs no GitHub token, webhook secret, or inbound
# SSH access.

: "${APP_IMAGE_REPOSITORY:?Set APP_IMAGE_REPOSITORY in /etc/konevo/deploy.env}"
: "${GITHUB_REPOSITORY:?Set GITHUB_REPOSITORY in /etc/konevo/deploy.env}"

readonly APP_DIR="${APP_DIR:-/opt/konevo/app}"
readonly COMPOSE_FILES="${COMPOSE_FILES:-${COMPOSE_FILE:-deploy/docker/compose.yaml}}"
readonly STATE_DIR="${STATE_DIR:-/var/lib/konevo}"
readonly STATE_FILE="${STATE_DIR}/deployed-version"
readonly LOCK_FILE="${STATE_DIR}/deploy.lock"

fail() {
  echo "konevo deploy: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

latest_release_tag() {
  curl --fail --silent --show-error --location --retry 3 \
    --connect-timeout 10 --max-time 30 \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases/latest" |
    jq --exit-status --raw-output '.tag_name'
}

main() {
  require_command docker
  require_command flock
  require_command git
  require_command curl
  require_command grep
  require_command jq

  [[ "$APP_IMAGE_REPOSITORY" =~ ^ghcr\.io/[a-z0-9._/-]+$ ]] ||
    fail "APP_IMAGE_REPOSITORY must be a lowercase ghcr.io image path"
  [[ "$GITHUB_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
    fail "GITHUB_REPOSITORY must use owner/repository format"

  mkdir -p "$STATE_DIR"
  exec 9>"$LOCK_FILE"
  flock -n 9 || exit 0

  cd "$APP_DIR"
  git diff --quiet && git diff --cached --quiet ||
    fail "deployment checkout has tracked changes; refusing to overwrite it"

  local version
  version="$(latest_release_tag)"
  [[ -n "$version" ]] || fail "no semver release tag found"
  [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid release tag: $version"

  local deployed_version=""
  [[ -f "$STATE_FILE" ]] && deployed_version="$(<"$STATE_FILE")"

  if [[ "$version" == "$deployed_version" ]]; then
    echo "konevo deploy: $version is already deployed"
    return 0
  fi

  git fetch --quiet --force origin "refs/tags/${version}:refs/tags/${version}"
  git rev-parse --verify --quiet "refs/tags/${version}^{commit}" >/dev/null ||
    fail "tag does not resolve to a commit: $version"
  git checkout --quiet --detach "$version"

  local app_image="${APP_IMAGE_REPOSITORY}:${version}"
  local compose_files=()
  local compose_file

  IFS=: read -r -a compose_files <<< "$COMPOSE_FILES"
  ((${#compose_files[@]} > 0)) || fail "COMPOSE_FILES must contain at least one Compose file"

  local compose=(docker compose --env-file .env)

  for compose_file in "${compose_files[@]}"; do
    [[ -n "$compose_file" ]] || fail "COMPOSE_FILES must not contain empty paths"
    compose+=(-f "$compose_file")
  done

  # Bootstrap infrastructure on the first release only. Routine releases do
  # not restart PostgreSQL or Caddy merely because application code changed.
  if ! APP_IMAGE="$app_image" "${compose[@]}" ps --status running --services | grep --fixed-strings --quiet db; then
    APP_IMAGE="$app_image" "${compose[@]}" up -d --wait db
  fi

  APP_IMAGE="$app_image" "${compose[@]}" pull app
  APP_IMAGE="$app_image" "${compose[@]}" up -d --no-deps app

  if ! APP_IMAGE="$app_image" "${compose[@]}" ps --status running --services | grep --fixed-strings --quiet caddy; then
    APP_IMAGE="$app_image" "${compose[@]}" up -d caddy
  fi

  printf '%s\n' "$version" > "$STATE_FILE"
  echo "konevo deploy: deployed $app_image"
}

main "$@"
