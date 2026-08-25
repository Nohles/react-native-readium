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
#     Download URL lives in external/kotlin-toolkit/gradle/gradle-daemon-jvm.properties;
#     set JAVA_HOME to a JBR 21 before running, or enable toolchain
#     auto-download for this invocation.
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

MODULES=(
  :readium:readium-shared:publishToMavenLocal
  :readium:readium-streamer:publishToMavenLocal
  :readium:readium-navigator:publishToMavenLocal
  # audiobook playback (issue #9): AudioNavigator is Media3-based and lives
  # outside readium-navigator; the ExoPlayer adapter provides the engine.
  :readium:navigators:media:readium-navigator-media-common:publishToMavenLocal
  :readium:navigators:media:readium-navigator-media-audio:publishToMavenLocal
  :readium:adapters:exoplayer:readium-adapter-exoplayer-audio:publishToMavenLocal
)

EXTRA_ARGS=()
if [[ "${SKIP_SIGNING:-0}" == "1" ]]; then
  # excludes the sign task of every module in one go
  EXTRA_ARGS+=(-x signMavenPublication)
fi

cd "$TOOLKIT"
./gradlew "${MODULES[@]}" "${EXTRA_ARGS[@]}" "$@"
