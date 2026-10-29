#!/usr/bin/env bash
# probe/assistant_role_probe.sh
#
# Software-only probe for the android.app.role.ASSISTANT role on an AOSP image.
# Drives `adb` from the CI runner and writes machine-readable results under
# $OUT_DIR (default: probe/).
#
# IMPORTANT: `adb shell input keyevent KEYCODE_ASSIST` / KEYCODE_VOICE_ASSIST is
# a SOFTWARE PROXY ONLY. This script makes NO claim about physical Side-button
# behaviour, firmware, or OEM-specific assist routing.

set -u

OUT_DIR="${1:-probe}"
mkdir -p "${OUT_DIR}"

log() { printf '%s\n' "$*"; }

json_escape() {
    printf '%s' "${1:-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n\r' '  '
}

have_adb=0
if command -v adb >/dev/null 2>&1; then have_adb=1; fi

API_LEVEL="${API_LEVEL:-}"
IMAGE_TARGET="${IMAGE_TARGET:-}"
FINGERPRINT="${RO_BUILD_FINGERPRINT:-}"
CANDIDATE_PKG="${CANDIDATE_PKG:-}"
APK_PATH="${APK_PATH:-}"

if [ "${have_adb}" -eq 1 ]; then
    if [ -z "${API_LEVEL}" ]; then
        API_LEVEL="$(adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
    fi
    if [ -z "${IMAGE_TARGET}" ]; then
        IMAGE_TARGET="$(adb shell getprop ro.build.type 2>/dev/null | tr -d '\r')"
    fi
    if [ -z "${FINGERPRINT}" ]; then
        FINGERPRINT="$(adb shell getprop ro.build.fingerprint 2>/dev/null | tr -d '\r')"
    fi
fi

API_LEVEL="${API_LEVEL:-unknown}"
IMAGE_TARGET="${IMAGE_TARGET:-default}"
FINGERPRINT="${FINGERPRINT:-unknown}"
[ -z "${API_LEVEL}" ] && API_LEVEL="unknown"
[ -z "${IMAGE_TARGET}" ] && IMAGE_TARGET="default"
[ -z "${FINGERPRINT}" ] && FINGERPRINT="unknown"

if [ -z "${CANDIDATE_PKG}" ] && [ "${have_adb}" -eq 1 ]; then
    DEFAULT_HOLDER="$(adb shell cmd role get-default-role-holder android.app.role.ASSISTANT 2>/dev/null | tr -d '\r')"
    if [ -n "${DEFAULT_HOLDER}" ] && [ "${DEFAULT_HOLDER}" != "null" ]; then
        CANDIDATE_PKG="${DEFAULT_HOLDER}"
    fi
fi
if [ -z "${CANDIDATE_PKG}" ]; then
    CANDIDATE_PKG="com.android.settings"
fi

if [ -z "${APK_PATH}" ]; then
    for p in "probe/assistant_dummy.apk" "assistant_dummy.apk" "${OUT_DIR}/assistant_dummy.apk"; do
        if [ -f "${p}" ]; then APK_PATH="${p}"; break; fi
    done
fi

log "===== assistant-role software probe ====="
log "image_target=${IMAGE_TARGET} api_level=${API_LEVEL}"
log "fingerprint=${FINGERPRINT}"
log "candidate_pkg=${CANDIDATE_PKG}"
log "NOTE: input keyevent is a SOFTWARE PROXY ONLY."
log "      This probe makes NO claim about physical Side-button behaviour."
log ""

if [ "${have_adb}" -eq 0 ]; then
    log "INCONCLUSIVE: adb binary not found; cannot run probe"
    cat > "${OUT_DIR}/result.json" <<EOF
{
  "image_target": "$(json_escape "${IMAGE_TARGET}")",
  "api_level": null,
  "role_add_supported": null,
  "role_add_exit_code": null,
  "role_holder_after": null,
  "assist_keyevent_dispatched": null,
  "raw_logcat_paths": [],
  "note": "adb not available; probe not executed"
}
EOF
    log "result.json written to ${OUT_DIR}/result.json"
    exit 0
fi

# 1. Baseline
BASELINE_FILE="${OUT_DIR}/role_holders_baseline.txt"
adb shell cmd role get-role-holders android.app.role.ASSISTANT > "${BASELINE_FILE}" 2>&1
BASE_RC=$?
log "Baseline get-role-holders exit=${BASE_RC}"
cat "${BASELINE_FILE}"
if [ ${BASE_RC} -eq 0 ]; then
    log "PASS: baseline get-role-holders completed (empty is acceptable)"
else
    log "INCONCLUSIVE: baseline get-role-holders returned ${BASE_RC}"
fi
log ""

# 2. Install dummy app (optional)
if [ -n "${APK_PATH}" ] && [ -f "${APK_PATH}" ]; then
    log "Installing prebuilt dummy APK: ${APK_PATH}"
    adb install -r "${APK_PATH}" > "${OUT_DIR}/install.log" 2>&1
    INSTALL_RC=$?
    if [ ${INSTALL_RC} -eq 0 ]; then
        log "PASS: dummy APK installed (${APK_PATH})"
    else
        log "FAIL: dummy APK install failed (exit ${INSTALL_RC})"
        cat "${OUT_DIR}/install.log"
    fi
else
    log "INCONCLUSIVE: no prebuilt dummy APK found (probe/assistant_dummy.apk)."
    log "  Reason: building an APK requires Android SDK build-tools not guaranteed"
    log "  in this environment; relying on existing candidate package. A clean"
    log "  negative is a valid result."
fi
log ""

# 3. add-role-holder
ADD_STDOUT_FILE="${OUT_DIR}/role_add_stdout.txt"
ADD_STDERR_FILE="${OUT_DIR}/role_add_stderr.txt"
: > "${ADD_STDOUT_FILE}"; : > "${ADD_STDERR_FILE}"
adb shell cmd role add-role-holder android.app.role.ASSISTANT "${CANDIDATE_PKG}" \
    > "${ADD_STDOUT_FILE}" 2> "${ADD_STDERR_FILE}"
ADD_RC=$?
ADD_COMBINED="${OUT_DIR}/role_add_combined.txt"
cat "${ADD_STDOUT_FILE}" "${ADD_STDERR_FILE}" > "${ADD_COMBINED}" 2>/dev/null || true

log "role add-role-holder exit=${ADD_RC}"
log "--- add stdout ---"; cat "${ADD_STDOUT_FILE}"
log "--- add stderr ---"; cat "${ADD_STDERR_FILE}"
log "--- end add ---"

ROLE_ADD_SUPPORTED="false"
if [ ${ADD_RC} -eq 0 ]; then
    if grep -qiE 'exception|error|not eligible|permission denied|unknown command|unsupported' "${ADD_COMBINED}" 2>/dev/null; then
        ROLE_ADD_SUPPORTED="false"
        log "INCONCLUSIVE: add-role-holder returned 0 but output contains an error marker (clean negative)"
    else
        ROLE_ADD_SUPPORTED="true"
        log "PASS: add-role-holder accepted (exit 0, no error marker)"
    fi
else
    ROLE_ADD_SUPPORTED="false"
    log "INCONCLUSIVE: add-role-holder rejected (exit ${ADD_RC}) - clean negative is a valid result"
fi
log ""

# 4. Re-run get-role-holders
AFTER_FILE="${OUT_DIR}/role_holders_after.txt"
adb shell cmd role get-role-holders android.app.role.ASSISTANT > "${AFTER_FILE}" 2>&1
AFTER_RC=$?
log "After get-role-holders exit=${AFTER_RC}"
cat "${AFTER_FILE}"
log ""

ROLE_HOLDER_AFTER="$(tr '\n' ' ' < "${AFTER_FILE}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

HOLDER_APPEARS="false"
if [ -n "${ROLE_HOLDER_AFTER}" ] && printf '%s' "${ROLE_HOLDER_AFTER}" | grep -qF "${CANDIDATE_PKG}"; then
    HOLDER_APPEARS="true"
fi

if [ "${HOLDER_APPEARS}" = "true" ]; then
    log "PASS: candidate ${CANDIDATE_PKG} now appears in role holders"
else
    if [ "${ROLE_ADD_SUPPORTED}" = "true" ]; then
        log "FAIL: add-role-holder reported success but candidate not found in holders"
    else
        log "INCONCLUSIVE: candidate not in holders (consistent with rejected add - clean negative)"
    fi
fi
log ""

# 5. Key injection (software proxy)
ASSIST_LOG="${OUT_DIR}/logcat_keyevent_assist.txt"
VOICE_LOG="${OUT_DIR}/logcat_keyevent_voice_assist.txt"

run_keyevent() {
    local key="$1"; local out="$2"; local rc=0
    adb shell logcat -c >/dev/null 2>&1 || true
    sleep 1
    adb shell input keyevent "${key}" >/dev/null 2>&1
    rc=$?
    sleep 2
    adb shell logcat -d > "${out}" 2>&1 || true
    log "  input keyevent ${key}: adb exit=${rc}; captured $(wc -l < "${out}" 2>/dev/null || echo 0) lines"
}

log "Key injection (SOFTWARE PROXY ONLY - not a Side-button claim):"
run_keyevent "KEYCODE_ASSIST" "${ASSIST_LOG}"
run_keyevent "KEYCODE_VOICE_ASSIST" "${VOICE_LOG}"
log ""

DISPATCHED="false"
if grep -qi "android.intent.action.ASSIST" "${ASSIST_LOG}" "${VOICE_LOG}" 2>/dev/null; then
    DISPATCHED="true"
fi
if [ "${DISPATCHED}" = "false" ]; then
    if grep -qiE "assist" "${ASSIST_LOG}" "${VOICE_LOG}" 2>/dev/null && \
       grep -qiE "start(ed)? (activity|service|proc)|am_start|dispatch" "${ASSIST_LOG}" "${VOICE_LOG}" 2>/dev/null; then
        DISPATCHED="true"
    fi
fi

if [ "${DISPATCHED}" = "true" ]; then
    log "PASS: assist intent dispatch observed in logcat (software proxy)"
else
    log "INCONCLUSIVE: no assist-intent dispatch observed in logcat (software proxy; image may not log it)"
fi
log ""

# 6. result.json
ASSIST_REL="${ASSIST_LOG#./}"
VOICE_REL="${VOICE_LOG#./}"
BASE_REL="${BASELINE_FILE#./}"
AFTER_REL="${AFTER_FILE#./}"
RAW_PATHS_JSON="[\"$(json_escape "${ASSIST_REL}")\", \"$(json_escape "${VOICE_REL}")\", \"$(json_escape "${BASE_REL}")\", \"$(json_escape "${AFTER_REL}")\"]"

case "${API_LEVEL}" in
    ''|*[!0-9]*) API_JSON="null" ;;
    *) API_JSON="${API_LEVEL}" ;;
esac

if [ -z "${ROLE_HOLDER_AFTER}" ]; then
    HOLDER_JSON="null"
else
    HOLDER_JSON="\"$(json_escape "${ROLE_HOLDER_AFTER}")\""
fi

if [ "${DISPATCHED}" = "true" ]; then DISPATCHED_JSON="true"; else DISPATCHED_JSON="false"; fi
if [ "${ROLE_ADD_SUPPORTED}" = "true" ]; then SUPPORTED_JSON="true"; else SUPPORTED_JSON="false"; fi

case "${ADD_RC}" in
    ''|*[!0-9]*) ADD_RC_JSON="null" ;;
    *) ADD_RC_JSON="${ADD_RC}" ;;
esac

FAILURE_TEXT="$(cat "${ADD_STDERR_FILE}" 2>/dev/null) $(cat "${ADD_STDOUT_FILE}" 2>/dev/null)"

cat > "${OUT_DIR}/result.json" <<EOF
{
  "image_target": "$(json_escape "${IMAGE_TARGET}")",
  "api_level": ${API_JSON},
  "role_add_supported": ${SUPPORTED_JSON},
  "role_add_exit_code": ${ADD_RC_JSON},
  "role_holder_after": ${HOLDER_JSON},
  "assist_keyevent_dispatched": ${DISPATCHED_JSON},
  "raw_logcat_paths": ${RAW_PATHS_JSON},
  "candidate_package": "$(json_escape "${CANDIDATE_PKG}")",
  "fingerprint": "$(json_escape "${FINGERPRINT}")",
  "role_add_failure_text": "$(json_escape "${FAILURE_TEXT}")",
  "note": "software proxy only; no claim about physical Side-button behaviour"
}
EOF

log "result.json written to ${OUT_DIR}/result.json"
log "===== probe complete ====="
exit 0
