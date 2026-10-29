#!/usr/bin/env bash
# Placeholder probe script (software half only). Full probe lands in t_78d54f09.
set -u
OUT_DIR="${1:-.}"
mkdir -p "${OUT_DIR}"
API_LEVEL="${API_LEVEL:-34}"
IMAGE_TARGET="${IMAGE_TARGET:-default}"
FINGERPRINT="${RO_BUILD_FINGERPRINT:-unknown}"

cat > "${OUT_DIR}/result.json" <<EOF
{
  "image_target": "${IMAGE_TARGET}",
  "api_level": ${API_LEVEL},
  "role_add_supported": null,
  "role_add_exit_code": null,
  "role_holder_after": null,
  "assist_keyevent_dispatched": null,
  "raw_logcat_paths": ["logcat.txt"],
  "note": "placeholder; full probe pending t_78d54f09"
}
EOF
echo "PLACEHOLDER probe ran (software proxy only; not a Side button claim)"
EOF
chmod +x /home/g/.hermes/kanban/boards/work/workspaces/t_f8712e73/repo/probe/assistant_role_probe.sh