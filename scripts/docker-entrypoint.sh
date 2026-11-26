#!/bin/sh
#
# Container entrypoint: tighten config permissions, then start radiusd
# in the foreground (or run whatever command was given instead).
#
# POSIX sh rather than bash: the Alpine runtime image has no bash.

set -e

readonly RADDB='/opt/etc/raddb'
# Files holding secrets; radiusd (running as radius) must read them.
readonly PROTECTED_FILES='clients.conf radiusd.conf mods-config/files/authorize'

#######################################
# Print a warning to STDERR.
# Arguments:
#   Message to print.
#######################################
warn() {
  echo "docker-entrypoint: warning: $*" >&2
}

#######################################
# Fix config permissions so radiusd will start. Best-effort: a
# read-only or host-owned bind mount must not stop the container.
# Globals:
#   RADDB
#   PROTECTED_FILES
#######################################
fix_permissions() {
  # radiusd refuses to start if the config directory is globally
  # writable.
  if ! chmod o-w "${RADDB}" 2>/dev/null; then
    warn "could not remove world-write from ${RADDB}"
  fi

  # POSIX sh has no "local"; the loop variable is global.
  for protected_file in ${PROTECTED_FILES}; do
    protected_file="${RADDB}/${protected_file}"
    [ -e "${protected_file}" ] || continue
    if ! { chgrp radius "${protected_file}" \
        && chmod 640 "${protected_file}"; } 2>/dev/null; then
      warn "could not set group radius, mode 0640 on ${protected_file}"
    fi
    # radiusd drops to the radius user before loading modules, so a
    # file it cannot read (e.g. a read-only 0600 mount) fails startup.
    # The first argument after the command is $0 ("sh"); the file is $1.
    # shellcheck disable=SC2016  # $1 expands in the radius user's shell.
    if ! su -s /bin/sh radius -c 'test -r "$1"' -- sh "${protected_file}"; then
      warn "user radius cannot read ${protected_file};" \
        "make it readable by group radius or mode 0644"
    fi
  done
}

#######################################
# Run radiusd in the foreground, or the given command.
# Arguments:
#   Optional command and/or radiusd flags.
#######################################
main() {
  # No arguments, or only flags (e.g. -X): treat them as radiusd flags.
  # Only works if every argument is a hyphenated flag; "-f arg" is fine,
  # "arg1 arg2" is not.
  if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
    set -- radiusd "$@"
  fi

  case "$1" in
    # Debian users are likely to call "freeradius" as well.
    radiusd | freeradius)
      shift
      fix_permissions
      exec radiusd -f "$@"
      ;;
  esac

  # Anything else, e.g. "sh": run it as given.
  exec "$@"
}

main "$@"
