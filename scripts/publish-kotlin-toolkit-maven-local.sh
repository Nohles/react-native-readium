#!/usr/bin/env bash
# Publish the Nohles/kotlin-toolkit submodule to the local Maven repository
# (~/.m2) so Android builds of this repo consume it instead of Maven Central.
#
# Why this exists: the toolkit requires AGP 9 while React Native 0.85 pins
# AGP 8.12, and a Gradle build may only load a single AGP version — so a
# composite build (includeBuild) is not possible. Publishing locally is the
# supported iteration loop for fork-level changes:
#
#   1. edit external/kotlin-toolkit
#   2. ./scripts/publish-kotlin-toolkit-maven-local.sh
#   3. rebuild the example app (clean the module if needed)
#
# Requirements (verified on a clean Linux machine):
#   - The pinned JDK toolchain the toolkit enforces: JetBrains Runtime 21.
#     Download URL lives in external/kotlin-toolkit/gradle/gradle-daemon-jvm.properties.
#     The daemon requirement is vendor-specific, so a stock Temurin/OpenJDK 21
#     is rejected; set TOOLKIT_JAVA_HOME to a JBR 21, or let this script find one
#     among the JDKs already listed in org.gradle.java.installations.paths.
#   - GPG signing: the toolkit signs all publications. Provide signing.keyId /
#     signing.password / signing.secretKeyRingFile in ~/.gradle/gradle.properties,
#     or pass SKIP_SIGNING=1 to strip signature tasks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLKIT="$ROOT/external/kotlin-toolkit"

if [[ ! -f "$TOOLKIT/settings.gradle.kts" ]]; then
  echo "error: $TOOLKIT is empty. Run: git submodule update --init --depth 1" >&2
  exit 1
fi

is_jbr_21() {
  local home="$1"
  [[ -x "$home/bin/java" ]] || return 1
  local version
  version="$("$home/bin/java" -version 2>&1)"
  grep -q '"21\.' <<<"$version" || return 1
  # The vendor only appears on the third -version line ("... (build ...)").
  grep -qi 'jetbrains\|JBR' <<<"$version"
}

resolve_jbr_21() {
  local candidate
  local searched=()
  for candidate in \
    "${TOOLKIT_JAVA_HOME:-}" \
    "$HOME/.gradle/jdks"/*/ \
    /tmp/opencode/provision/jbrsdk*/ \
    /opt/jbr* \
    /usr/local/jbr*; do
    [[ -d "$candidate" ]] || continue
    searched+=("$candidate")
    if is_jbr_21 "$candidate"; then
      printf '%s\n' "${candidate%/}"
      return 0
    fi
  done

  cat >&2 <<EOF
error: the kotlin-toolkit needs a JetBrains Runtime 21 (its Gradle daemon
       requirement is vendor-specific, so a stock JDK 21 is not accepted).

Searched: ${searched[*]:-<no candidates>}
Set TOOLKIT_JAVA_HOME=/path/to/jbr-21, or add one to
org.gradle.java.installations.paths in ~/.gradle/gradle.properties. A downloadable
build is listed in $TOOLKIT/gradle/gradle-daemon-jvm.properties.
EOF
  return 1
}

if ! JBR="$(resolve_jbr_21)"; then
  exit 1
fi

# The daemon runs on the JBR; gradle.properties also gains the JBR as a known
# toolchain location so the same JVM satisfies both the daemon and the toolchain
# request without a second download.
export JAVA_HOME="$JBR"
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.java.installations.paths=$JBR"
echo "using toolkit JDK: $JBR"

# The toolkit is an Android library and needs an SDK on the path. Resolve the
# usual locations rather than failing with Gradle's "SDK location not found",
# which does not say where it looked.
if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
  for candidate in \
    "$HOME/Android/Sdk" \
    "$HOME/Library/Android/sdk" \
    "$HOME/AppData/Local/Android/Sdk" \
    /usr/lib/android-sdk \
    /opt/android-sdk \
    /usr/local/lib/android/sdk; do
    if [[ -d "$candidate" ]]; then
      export ANDROID_HOME="$candidate"
      echo "using Android SDK: $ANDROID_HOME"
      break
    fi
  done
fi

if [[ -z "${ANDROID_HOME:-}" && -z "${ANDROID_SDK_ROOT:-}" ]]; then
  echo "error: no Android SDK found. Set ANDROID_HOME to your SDK path." >&2
  exit 1
fi

# Every org.readium.kotlin-toolkit coordinate declared in android/build.gradle
# must appear here. A coordinate that is missing from this list does not fail the
# build — Gradle silently falls back to Maven Central for that artifact alone, so
# one module links against the fork and its neighbour against upstream. That was
# the case for the two pdfium adapters, which made PDF the only format built
# against a different toolkit than everything else.
MODULES=(
  :readium:readium-shared:publishToMavenLocal
  :readium:readium-streamer:publishToMavenLocal
  :readium:readium-navigator:publishToMavenLocal
  # audiobook playback (issue #9): AudioNavigator is Media3-based and lives
  # outside readium-navigator; the ExoPlayer adapter provides the engine.
  :readium:navigators:media:readium-navigator-media-common:publishToMavenLocal
  :readium:navigators:media:readium-navigator-media-audio:publishToMavenLocal
  :readium:adapters:exoplayer:readium-adapter-exoplayer-audio:publishToMavenLocal
  # PDF navigator + its document layer. Pulls com.github.marain87:pdfium-android
  # from jitpack, which the toolkit already declares as a repository.
  :readium:adapters:pdfium:readium-adapter-pdfium-document:publishToMavenLocal
  :readium:adapters:pdfium:readium-adapter-pdfium-navigator:publishToMavenLocal
)

# Signing: the fork signs every publication. Signing only has to be stripped when
# no key is configured — and in that case `-x signMavenPublication` is not
# enough on its own, because the vanniktech plugin registers a separate
# signature task per artifact. Excluding the aggregate leaves the *sources jar*
# signature attached to the publication with no task to produce it, and
# `publishToMavenLocal` then fails on a missing `release-sources.jar.asc`.
# So disable the tasks rather than skipping the aggregate.
skip_signing() {
  [[ "${SKIP_SIGNING:-0}" == "1" ]] && return 0
  ! grep -qE '^[[:space:]]*signing\.keyId[[:space:]]*=' "${HOME}/.gradle/gradle.properties" 2>/dev/null
}

EXTRA_ARGS=()
if skip_signing; then
  echo "no signing key configured — publishing unsigned artifacts"
  EXTRA_ARGS+=(
    -I <(cat <<'GRADLE'
// Detach every signature task and artifact so `publishToMavenLocal` writes
// plain jars. The fork's `signAllPublications()` assumes a release key exists.
allprojects { project ->
    project.tasks.configureEach { task ->
        def name = task.name.toLowerCase()
        if (name.startsWith('sign') && !name.startsWith('signing')) {
            task.enabled = false
        }
    }
}
GRADLE
    )
  )
fi

cd "$TOOLKIT"
./gradlew "${MODULES[@]}" "${EXTRA_ARGS[@]}" "$@"

# Fail loudly rather than leaving a half-published fork behind, which reads as a
# successful build and then misbehaves at runtime in whichever format happens to
# touch the missing artifact. The expected set is parsed from android/build.gradle
# so it can never drift from what the Android build actually resolves.
LOCAL_REPO="${HOME}/.m2/repository/org/readium/kotlin-toolkit"
expected=()
while read -r artifact; do
  expected+=("$artifact")
done < <(
  grep -oE '"org\.readium\.kotlin-toolkit:[^"]+"' "$ROOT/android/build.gradle" |
    sed -E 's/.*:([^:]+):.*/\1/' | sort -u
)

if [[ ${#expected[@]} -eq 0 ]]; then
  echo "error: found no org.readium.kotlin-toolkit coordinates in android/build.gradle" >&2
  exit 1
fi

missing=()
for artifact in "${expected[@]}"; do
  if [[ ! -d "$LOCAL_REPO/$artifact" ]]; then
    missing+=("$artifact")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "error: these artifacts are still absent from $LOCAL_REPO:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "       Android builds will silently resolve them from Maven Central." >&2
  exit 1
fi

echo "published all ${#expected[@]} kotlin-toolkit coordinates to $LOCAL_REPO:"
printf '  %s\n' "${expected[@]}"
