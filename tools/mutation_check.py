#!/usr/bin/env python3
"""Apply known defects to the repository and require the guard suite to catch each.

A green suite is not evidence that the suite can fail. Each entry below
reintroduces one defect a guard exists for, and the battery fails unless the
suite goes red with that guard's own assertion. The mechanism is extracted
from Honest Sudoku's CI.

Two rules:

  * A mutation must really change the file. A pattern that no longer matches
    would silently test nothing, so it is reported as BROKEN.
  * A mutation must leave the file parseable (YAML, shell) and the Dart
    analyzable. One that breaks the syntax makes the suite fail for the wrong
    reason, so it is reported as BROKEN rather than caught.

Usage:  tools/mutation_check.py [--list] [--only SUBSTRING] [--self-test]
Exit:   0 every mutation was caught
        1 at least one survived (the suite stayed green)
        2 the battery could not run (dirty tree, bad pattern, unparseable)
"""
from __future__ import annotations

import argparse
import json
import dataclasses
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# The guard suite, minus any `slow`-tagged test.
#
# The suite runs once per mutation, so an expensive guard multiplies the whole
# battery's time. Such a guard tags itself `slow` (here,
# test/guards/upload_cert_test.dart, which starts JVMs), and only the
# mutations that need it set `slow=True` to run SUITE_SLOW.
SUITE = ["flutter", "test", "--no-pub", "--tags", "guard",
         "--exclude-tags", "slow"]
SUITE_SLOW = ["flutter", "test", "--no-pub", "--tags", "guard"]
IN_FLIGHT = ROOT / ".mutation_check_in_flight"


@dataclasses.dataclass(frozen=True)
class Mutation:
    issue: str
    name: str
    path: str
    apply: object  # str -> str
    why: str
    expect: str = ""
    also: tuple = ()
    slow: bool = False
    creates: tuple = ()
    deletes: str = ""
    replaces_with: tuple = ()
    adds: tuple = ()
    """`expect` is a substring of the reason the RIGHT assertion prints when it
    fires. Without it the battery measures "the suite went red", which is not
    "this guard caught it": an unrelated test reading the same file could go
    red instead.

    `creates` names paths the mutated code WRITES while the suite runs, so
    they are removed afterwards; restoring the mutated file alone would leave
    them in the tree for the next `git add -A`.

    `also` carries further `(path, apply)` edits, for a defect that cannot be
    written truthfully in one file.

    `deletes` names one file removed for the run and `replaces_with` holds
    `(target, fixture)` pairs whose fixture bytes overwrite the target: the
    defects a text substitution cannot express -- a missing raster, the
    template's icon back in place. Both are byte snapshots restored in the
    same try/finally as the text edits, and `--self-test` proves that round
    trip byte-identical. `adds` holds `(path, text)` pairs written for the
    run -- a new file, such as a manifest in a source set that does not exist
    (#30) -- and deleted afterwards with any directories they needed; a path
    that already exists makes the mutation BROKEN. A mutation of these kinds
    may leave `path` empty.
    (Ported from Honest Solitaire's battery, #18.)
    """


def sub(pattern: str, replacement: str, count: int = 1, flags: int = 0):
    """A regex substitution that must match, with `\\1`-style group expansion."""

    def go(text: str) -> str:
        out, n = re.subn(pattern, replacement, text, count=count, flags=flags)
        if n == 0:
            raise LookupError(f"pattern never matched: {pattern!r}")
        return out

    return go


def append(block: str):
    return lambda text: text.rstrip("\n") + "\n" + block


def chain(*steps):
    """Several substitutions on one file, in order.

    A defect that MOVES something is two edits; writing it as one -- a delete
    without the matching insert -- tests a different defect than its name
    claims.
    """

    def go(text: str) -> str:
        for step in steps:
            text = step(text)
        return text

    return go


def flip_orientation(manifest: str) -> str:
    """Lock MainActivity to an orientation other than the one it has, or lock
    it if it has none: the identity guard's defect, whatever the app chose."""
    lock = r'android:screenOrientation="([^"]*)"'
    m = re.search(lock, manifest)
    if m:
        other = "portrait" if m.group(1) != "portrait" else "landscape"
        return re.sub(lock, f'android:screenOrientation="{other}"', manifest, count=1)
    return sub(r'(android:name="\.MainActivity")',
               r'\1 android:screenOrientation="portrait"')(manifest)


MUTATIONS: list[Mutation] = [
    # Each entry is a defect this repository's guards must catch. The first
    # field names the area; an app adds its own entries the same way, named
    # after the issue that found the defect.
    Mutation("ci", "the gate step becomes advisory", ".github/workflows/ci.yml",
             sub(r"run: tools/gate\.sh$", "run: tools/gate.sh || true", flags=re.M),
             "CI would run the gate and ignore its verdict",
             'no step runs tools/gate.sh exactly'),

    # identity -- android_identity_test.dart
    Mutation("identity", "the app's orientation lock changes",
             "android/app/src/main/AndroidManifest.xml",
             flip_orientation,
             "the app would rotate into layouts nobody designed",
             'android-identity-orientation:'),
    Mutation("identity", "applicationId drifts from the identity file",
             "android/app/build.gradle.kts",
             sub(r'applicationId = "[^"]*"', 'applicationId = "com.acme.other"'),
             "the bundle would upload under a package nobody registered",
             'android-identity-gradle:'),
    Mutation("identity", "minSdk drifts from the identity file",
             "android/app/build.gradle.kts",
             sub(r"minSdk = \d+", "minSdk = 21"),
             "the app would install on devices it was never tested on",
             'android-identity-min-sdk:'),
    Mutation("identity", "the launcher label drifts",
             "android/app/src/main/AndroidManifest.xml",
             sub(r'(<application\b[^>]*?android:label=")[^"]*"', r'\1Other"', flags=re.S),
             "the launcher would show a name the identity file does not",
             'android-identity-label:'),
    Mutation("identity", "a workflow reads the package from a repository variable",
             ".github/workflows/play-api-check.yml",
             sub(r"PACKAGE: \S+$", "PACKAGE: ${{ vars.APP_PACKAGE_ID }}", flags=re.M),
             "an unset variable would check or upload the wrong package",
             'android-identity-package:'),
    Mutation("identity", "the release stops refusing the placeholder id",
             ".github/workflows/release.yml",
             sub(r"      - id: identity\n.*?\n        run: tools/release_identity\.sh\n\n",
                 "", flags=re.S),
             "a clone that was never renamed would build and sign a release",
             'release-identity-order:'),
    Mutation("identity", "the release pre-flight accepts the placeholder id",
             "tools/release_identity.sh",
             sub(r'(first" >&2\n)    exit 1\n', r"\1"),
             "the pre-flight would pass a com.example.* id",
             'release-identity: the placeholder id was not refused'),

    # dependencies -- dependency_policy_example_test.dart
    Mutation("deps", "a package loses its justification", "pubspec.yaml",
             sub(r"^(  yaml: \S+) # why: .*$", r"\1", flags=re.M),
             "a third-party package would ship with no recorded reason",
             'missing-why: 1 offender'),
    Mutation("deps", "a blocked package hides behind a commented header",
             "pubspec.yaml",
             sub(r"^dev_dependencies:$",
                 "dev_dependencies: # test only\n  google_mobile_ads: ^5.0.0 # why: mutation",
                 flags=re.M),
             "an ads SDK would pass the dependency guard",
             'dependency-policy: 1 offender'),
    Mutation("deps", "a network client is added", "pubspec.yaml",
             sub(r"^dependencies:\n", "dependencies:\n  http: ^1.2.0 # why: mutation\n",
                 flags=re.M),
             "the app would carry an HTTP client, against invariant 1",
             'dependency-policy: 1 offender'),

    # manifests -- manifest_permission_example_test.dart
    Mutation("manifest", "the main manifest requests a permission",
             "android/app/src/main/AndroidManifest.xml",
             sub(r"(<manifest [^>]*>\n)",
                 r'\1    <uses-permission android:name="android.permission.INTERNET"/>\n'),
             "the app would ask for network access",
             'permission-guard: 1 offender'),
    Mutation("manifest", "the main manifest declares a permission",
             "android/app/src/main/AndroidManifest.xml",
             sub(r"(<manifest [^>]*>\n)",
                 r'\1    <permission android:name="com.acme.P" />\n'),
             "a permission declaration would ship, seen only by the bundle scan",
             'manifest-permission-element: 1 offender'),
    Mutation("manifest", "a manifest strips a permission at build time",
             "android/app/src/debug/AndroidManifest.xml",
             sub(r'<uses-permission android:name="android.permission.INTERNET"/>',
                 '<uses-permission android:name="android.permission.INTERNET" tools:node="remove"/>'),
             "a removal rule would hide a plugin's permission instead of refusing the plugin",
             'manifest-removal-rule: 1 offender'),
    Mutation("manifest", "a new source set requests a permission (#30)",
             "", None,
             "a release-only manifest could ask for network access unseen",
             'permission-guard: 1 offender',
             adds=(("android/app/src/release/AndroidManifest.xml",
                    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
                    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
                    '</manifest>\n'),)),
    Mutation("manifest", "the debug manifest declares a permission",
             "android/app/src/debug/AndroidManifest.xml",
             sub(r"(<manifest [^>]*>\n)",
                 r'\1    <permission android:name="com.acme.P" />\n'),
             "a declaration outside the main manifest would reach only the bundle scan",
             'manifest-permission-element: 1 offender'),
    Mutation("manifest", "a manifest removes an attribute at build time",
             "android/app/src/debug/AndroidManifest.xml",
             sub(r'<uses-permission android:name="android.permission.INTERNET"/>',
                 '<uses-permission android:name="android.permission.INTERNET" tools:remove="android:maxSdkVersion"/>'),
             "a tools:remove rule would rewrite a plugin's request unseen",
             'manifest-removal-rule: 1 offender'),

    # bundle scan -- bundle_scan_test.dart
    Mutation("bundle", "a wrong package is reported as a permission",
             "tools/check_aab.sh",
             sub(r'(echo "PACKAGE MISSING: expected \$PACKAGE in \$AAB" >&2\n)  exit 2\n',
                 r"\1"),
             "a wrong package id would be misdiagnosed as permissions",
             'bundle-scan: a wrong package was not diagnosed as one'),
    Mutation("bundle", "the bundle scan waves through a third-party request",
             "tools/check_aab.sh",
             sub(r'  else\n    OFFENDERS="\$OFFENDERS\$name\n"\n  fi\ndone <<EOF\n\$PERM_ENTRIES',
                 '  else\n    :\n  fi\ndone <<EOF\n$PERM_ENTRIES'),
             "an SDK's own permission request would ship past the scan",
             'bundle-scan: a third-party permission request was not refused'),
    Mutation("bundle", "the bundle scan waves through a declaration",
             "tools/check_aab.sh",
             sub(r'    OFFENDERS="\$OFFENDERS\$name \(declared\)\n"\n', "    :\n"),
             "a library's permission declaration would ship past the scan",
             'bundle-scan: a declared permission was not refused'),

    # signing -- signing_guard_test.dart
    Mutation("signing", "a release request without every key debug-signs",
             "android/app/build.gradle.kts",
             sub(r"if \(hsReleaseRequested && !hsSigningComplete\) \{\n[^\n]*\n[^\n]*\n\}\n", ""),
             "HS_RELEASE=1 with a missing secret would build a debug-signed bundle",
             'signing-fail-closed: 1 offender'),
    Mutation("signing", "a partial HS_* set debug-signs",
             "android/app/build.gradle.kts",
             sub(r"if \(hsPresent\.isNotEmpty\(\) && !hsSigningComplete\) \{\n[^\n]*\n[^\n]*\n\}\n", ""),
             "a typo in one variable name would silently debug-sign",
             'signing-fail-closed: 1 offender'),
    Mutation("signing", "git stops ignoring keystores", ".gitignore",
             sub(r"^\*\.keystore\n", "", flags=re.M),
             "a keystore dropped in the tree could be committed",
             'key-material-not-ignored:'),

    # signing -- signing_readme_test.dart
    Mutation("signing", "the README's fingerprint drifts from the certificate",
             "android/signing/README.md",
             sub(r"^(\| SHA-256 \| `)[0-9A-F]{2}", r"\g<1>00", flags=re.M),
             "the owner would compare the Console against the wrong key",
             'signing-readme: README says'),

    # workflow permissions -- workflow_permissions_test.dart (#20)
    Mutation("ci", "the PR workflow grants write to its token",
             ".github/workflows/ci.yml",
             sub(r"^permissions:\n  contents: read$", "permissions:\n  contents: write",
                 flags=re.M),
             "a pull request's code would run with a token that can push",
             'workflow-permissions: 1 offender'),

    # play-promote.yml's own barriers -- play_promote_workflow_test.dart (#44)
    Mutation("promote", "the promote workflow also runs on push",
             ".github/workflows/play-promote.yml",
             sub(r"^on:\n  workflow_dispatch:", "on:\n  push:\n    branches: [main]\n  workflow_dispatch:", flags=re.M),
             "a merge could start a promotion no person asked for",
             'promote-trigger: play-promote.yml runs on more than workflow_dispatch'),
    Mutation("promote", "production becomes a track choice",
             ".github/workflows/play-promote.yml",
             sub(r"options: \[internal, alpha, beta\]", "options: [internal, alpha, beta, production]"),
             "the dispatch form would offer production",
             'promote-options: production is offered as a track'),
    Mutation("promote", "the promote step stops calling the script",
             ".github/workflows/play-promote.yml",
             sub(r"tools/play_promote\.sh \"\$PACKAGE\"", 'echo promoted "$PACKAGE"'),
             "the script's own production refusal would be bypassed",
             'promote-script: the promote step does not call tools/play_promote.sh'),

    # privacy policy -- privacy_policy_test.dart
    Mutation("docs", "the privacy policy names another package", "docs/privacy.md",
             sub(r"`com\.honestarcade\.chess`", "`com.honestarcade.solitaire`"),
             "the Play listing would link a policy for a different app",
             'privacy-policy: 1 offender'),

    # launcher icon and start screen -- launcher_icon_test.dart (#18)
    Mutation("icon", "the template's default icon is back at one density",
             "", None,
             "the store build would ship Flutter's placeholder icon again",
             'launcher-template: 1 offender',
             replaces_with=(("android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png",
                             "test/fixtures/template_ic_launcher_xxxhdpi.png"),)),
    Mutation("icon", "the adaptive icon loses its themed layer",
             "android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml",
             sub(r"\n    <monochrome [^\n]*/>", ""),
             "Android 13 themed icons would show a generic tile",
             'launcher-adaptive: 1 offender'),
    Mutation("icon", "one source's rook drifts from the others",
             "assets/brand/android-foreground.svg",
             sub(r'd="M 22\.6 15 H', 'd="M 22.6 16 H'),
             "the icon's layers would stop agreeing on the mark",
             'launcher-sources: the inline mark copies differ'),
    Mutation("icon", "the Android 12 splash loses the mark",
             "android/app/src/main/res/values-v31/styles.xml",
             sub(r'\n\s*<item name="android:windowSplashScreenAnimatedIcon">[^\n]*', ''),
             "the system splash would show the icon Android forces, not the mark",
             'launcher-splash: 1 offender'),
    Mutation("icon", "the app's window turns white behind the first frame (#28)",
             "android/app/src/main/res/values/styles.xml",
             sub(r'(<style name="NormalTheme"[^>]*>\s*<item name="android:windowBackground">)@color/launch_navy',
                 r'\1@android:color/white'),
             "a white frame would flash between the launch screen and the app",
             'launcher-splash: 1 offender'),
    Mutation("icon", "the rook outgrows the adaptive icon's safe zone (#31)",
             "assets/brand/android-foreground.svg",
             sub(r"scale\(1\.32\)", "scale(2.4)"),
             "a circle mask would clip the rook while the corners still fit",
             'launcher-safe-zone: the rook reaches',
             also=(("assets/brand/icon-tile.svg", sub(r"scale\(1\.32\)", "scale(2.4)")),
                   ("assets/brand/icon-legacy.svg", sub(r"scale\(1\.32\)", "scale(2.4)")))),
    Mutation("icon", "a start-screen mark raster goes missing",
             "", None,
             "the pre-12 start screen would fail to inflate its drawable",
             'launcher-rasters: 1 offender',
             deletes="android/app/src/main/res/drawable-xhdpi/launch_mark.png"),

    # template leftovers -- template_leftovers_test.dart (#35)
    Mutation("identity", "the placeholder app's name comes back in the README",
             "README.md",
             sub(r"^# Honest Chess$", "# Honest Chess\n\nFormerly <Your App Name>.", flags=re.M),
             "a doc would describe the template's app, not this one",
             'template-leftovers: 1 offender'),

    # key generation -- setup_scripts_test.dart (#36)
    Mutation("setup", "the upload key accepts a short password",
             "tools/make_upload_key.sh",
             sub(r'-lt 32 \]', '-lt 12 ]'),
             "the key that signs every release could be generated with a weak password",
             'character password was not refused'),

    # scheduled tests -- scheduled_tests_test.dart (#37, #38)
    Mutation("ci", "a scheduled test job passes having run nothing",
             "tools/counted_tests.sh",
             sub(r'  exit 3\n', '  exit 0\n'),
             "a scheduled job would stay green while testing nothing",
             'scheduled-tests: an empty run was not refused'),
    Mutation("ci", "the PR gate runs the weekly tests",
             "tools/gate.sh",
             sub(r'"flutter test --no-pub --exclude-tags weekly"', '"flutter test --no-pub"'),
             "every pull request would pay for the slow tier",
             'weekly-gate: tools/gate.sh would run the weekly tests'),
    Mutation("ci", "the weekly workflow bypasses the empty-run refusal",
             ".github/workflows/weekly.yml",
             sub(r'run: tools/weekly_tests\.sh', 'run: flutter test --no-pub --tags weekly'),
             "an empty weekly run would read as a pass",
             'weekly-workflow: the job does not run tools/weekly_tests.sh'),
    Mutation("ci", "the weekly tag is no longer declared (#46)",
             "dart_test.yaml",
             sub(r"\n  weekly:\n    description: >-\n(      .*\n)+", "\n"),
             "the weekly tier's tag would silently mean nothing",
             'weekly-gate: dart_test.yaml does not declare the weekly tag'),
    Mutation("ci", "a scheduled run's summary stops saying nothing ran (#45)",
             "tools/counted_tests.sh",
             sub(r'  summarise "\*\*\$counts\*\*" "\$label: no test ran — refusing to pass empty"\n', ''),
             "a red scheduled run would not say why in its summary",
             'scheduled-summary: the job summary does not say what ran'),
    Mutation("ci", "the weekly schedule is on with no weekly test (#47)",
             "test/engine/strength_ladder_test.dart",
             sub(r"^@Tags\(\['weekly'\]\)\n", "", flags=re.M),
             "the weekly job would fail every Sunday",
             'weekly-schedule: weekly.yml is scheduled but no test is tagged weekly',
             # The schedule is on (#69), so the defect is every weekly-tagged
             # file losing its tag: `grep -rl "Tags(\['weekly'" test/` lists them.
             also=(("test/engine/perft_weekly_test.dart",
                    sub(r"^@Tags\(\['weekly'\]\)\n", "", flags=re.M)),
                   ("test/engine/computer_clock_weekly_test.dart",
                    sub(r"^@Tags\(\['weekly'\]\)\n", "", flags=re.M)))),
    Mutation("ci", "CI's guard step would run weekly-tagged guards (#48)",
             ".github/workflows/ci.yml",
             sub(r"--tags guard --exclude-tags weekly", "--tags guard"),
             "a slow test tagged guard and weekly would run on every PR",
             'weekly-gate: a ci.yml test step would run weekly-tagged tests'),
    Mutation("ci", "ci.yml's gate job runs the device tests (#54)",
             ".github/workflows/ci.yml",
             sub(r"(      - id: gate\n)", "      - id: device\n        name: Device tests\n        run: flutter test --no-pub --exclude-tags weekly integration_test\n\n\\1"),
             "every PR would need a device and fail without one",
             'device-gate: a ci.yml step would need a device'),
    Mutation("ci", "the device workflow bypasses the empty-run refusal",
             ".github/workflows/device.yml",
             sub(r'script: tools/device_tests\.sh', 'script: flutter test integration_test'),
             "an emulator run that found no test would read as a pass",
             'device-workflow: the emulator does not run tools/device_tests.sh'),
    Mutation("ci", "the emulator binary floats to whatever sdkmanager serves",
             ".github/workflows/device.yml",
             sub(r'\n          emulator-build: "\d+"', ''),
             "a new emulator release would enter the nightly job unreviewed",
             'device-workflow: the emulator binary is not pinned'),
    Mutation("ci", "the release build reuses pub get's plugin registrant",
             ".github/workflows/release.yml",
             sub(r"flutter build appbundle --release \\", r"flutter build appbundle --release --no-pub \\"),
             "the next tagged release would fail to compile the dev-only plugin",
             'release-build: a release build with --no-pub'),
    Mutation("ci", "the PR gate tries to run the device tests",
             "tools/gate.sh",
             sub(r'"flutter test --no-pub --exclude-tags weekly"',
                 '"flutter test --no-pub --exclude-tags weekly test integration_test"'),
             "every pull request would need a device and fail without one",
             'device-gate: tools/gate.sh would need a device'),

    # gate -- gate_failure_test.dart
    Mutation("gate", "the gate exits 0 after a failing step", "tools/gate.sh",
             sub(r'(echo "GATE FAILED at \$label \(exit \$status\)" >&2\n)    exit "\$status"',
                 r'\1    exit 0'),
             "a failing gate would read as a pass to CI",
             'gate-failure-path: a failing step did not fail the gate'),
    Mutation("gate", "the build's status is read from tee", "tools/gate.sh",
             sub(r"status=\$\{PIPESTATUS\[0\]\}", "status=${PIPESTATUS[1]}"),
             "a failing build would be reported with tee's exit status",
             'gate-build-failure:'),

    # secrets -- workflow_secrets_test.dart
    Mutation("secrets", "the keystore step turns on shell tracing",
             ".github/workflows/release.yml",
             sub(r"(      - id: keystore\n(?:        [^\n]*\n)*?        run: \|\n)          set -euo pipefail",
                 r"\1          set -x\n          set -euo pipefail"),
             "the keystore password would be echoed into a public log",
             'workflow-secret-exposure: 1 offender'),
    Mutation("secrets", "a secret is pasted into a script",
             ".github/workflows/release.yml",
             sub(r"-storepass:env HS_KEYSTORE_PASS",
                 '-storepass "${{ secrets.HS_KEYSTORE_PASS }}"'),
             "the password would be part of the script text GitHub logs",
             'workflow-secret-exposure: 1 offender'),
    Mutation("secrets", "a secret is put in scope for the whole job",
             ".github/workflows/release.yml",
             sub(r'(    env:\n      FLUTTER_SUPPRESS_ANALYTICS: "true"\n)',
                 r"\1      HS_KEY_PASS: ${{ secrets.HS_KEY_PASS }}\n"),
             "every step, and every action it runs, would hold the key password",
             'workflow-secret-exposure: 1 offender'),
    Mutation("secrets", "a tools/ script turns on tracing", "tools/check_aab.sh",
             sub(r"^set -euo pipefail$", "set -euxo pipefail", flags=re.M),
             "a script handed a secret would echo it",
             'script-tracing: 1 offender'),

    # release -- release_workflow_test.dart
    Mutation("release", "the release stops waiting for the gate",
             ".github/workflows/release.yml",
             sub(r"^    needs: gate\n", "", flags=re.M),
             "a tag could ship a bundle the gate never passed",
             'release-order: 1 offender'),
    Mutation("release", "the release stops checking the certificate",
             ".github/workflows/release.yml",
             sub(r"      - id: cert\n        name: Verify the signing certificate\n"
                 r"        run: tools/verify_upload_cert\.sh\n\n", ""),
             "a bundle signed by the wrong key would be uploaded",
             'release-order: 1 offender'),
    Mutation("release", "the permission scan can be skipped",
             ".github/workflows/release.yml",
             sub(r"(        run: tools/check_aab\.sh\n)", r"\1        if: false\n"),
             "the scan would report skipped and the upload would go ahead",
             'release-order: 1 offender'),
    Mutation("release", "the release build stops failing closed",
             ".github/workflows/release.yml",
             sub(r'          HS_RELEASE: "1"\n', ""),
             "a missing signing secret would ship a debug-signed bundle",
             'release-order: 1 offender'),
    Mutation("release", "the decoded keystore outlives a failed job",
             ".github/workflows/release.yml",
             sub(r"(      - id: shred\n        name: [^\n]*\n)        if: always\(\)\n",
                 r"\1"),
             "a failed release would leave the keystore on the runner",
             'release-order: 1 offender'),

    # ci -- workflow_structure_example_test.dart
    Mutation("ci", "the mutations check becomes advisory",
             ".github/workflows/ci.yml",
             sub(r"run: tools/mutation_check\.py$",
                 "run: tools/mutation_check.py || true", flags=re.M),
             "a surviving mutation would leave the required check green",
             'no step runs tools/mutation_check.py'),
    Mutation("ci", "pull requests stop running CI", ".github/workflows/ci.yml",
             sub(r"^on:\n  pull_request:\n", "on:\n", flags=re.M),
             "a pull request would merge with no checks at all",
             'ci.yml no longer triggers'),
    Mutation("ci", "the mutations job may fail quietly",
             ".github/workflows/ci.yml",
             sub(r"(  mutations:\n    runs-on: ubuntu-latest\n)",
                 r"\1    continue-on-error: true\n"),
             "a surviving mutation would not fail the run",
             'workflow-lenient-check: 1 offender'),
    Mutation("ci", "the PR bundle is named after the merge commit",
             ".github/workflows/ci.yml",
             sub(r"github\.event\.pull_request\.head\.sha \}\}", "github.sha }}"),
             "a downloaded PR bundle would name a commit that is not in the PR",
             'workflow-artifact-name:'),

    # release scripts -- release_scripts_test.dart, upload_cert_test.dart
    Mutation("scripts", "ci_version.sh accepts a leading zero", "tools/ci_version.sh",
             sub(r'  die "ref \'\$ref\' has a leading zero in a version component"',
                 "  true"),
             "v01.2.3 would ship as version 01.2.3",
             'release-scripts: ci_version.sh accepted'),
    Mutation("scripts", "ci_version.sh accepts attempt 10", "tools/ci_version.sh",
             sub(r"grep -qE '\^\[1-9\]\$'", "grep -qE '^[0-9]+$'"),
             "attempt 10 of run N would reuse attempt 0 of run N+1's version code",
             'release-scripts: ci_version.sh accepted'),
    Mutation("scripts", "any gh failure reads as no release",
             "tools/attach_release_asset.sh",
             sub(r"grep -qiE '[^']*' \"\$view_err\"", "grep -qiE '.' \"$view_err\""),
             "a 5xx or a token problem would skip the attach on a green run",
             'release-scripts: a gh failure was treated as no release'),
    Mutation("scripts", "the attached asset is never compared",
             "tools/attach_release_asset.sh",
             sub(r'if \[ "\$\(sha256 "\$AAB"\)" != [^\n]*\]; then', "if false; then"),
             "a corrupted upload would be reported as verified",
             'release-scripts: a corrupted asset passed'),
    Mutation("scripts", "the certificate check accepts any signed bundle",
             "tools/verify_upload_cert.sh",
             sub(r'if \[ "\$BUNDLE_FP" = "\$PEM_FP" \]; then',
                 'if [ -n "$BUNDLE_FP" ]; then'),
             "a bundle signed by the wrong key would read as MATCH",
             'upload-cert: a bundle signed by another key passed',
             slow=True),

    # setup scripts -- setup_scripts_test.dart
    Mutation("setup", "make_upload_key.sh overwrites an existing key",
             "tools/make_upload_key.sh",
             sub(r"(move BOTH files aside deliberately.\" >&2\n)    exit 2\n", r"\1"),
             "a second run would replace the key Play enrolled",
             'setup-scripts: make_upload_key.sh wrote over'),
    Mutation("setup", "set_ci_secrets.sh uploads after a failed pre-flight",
             "tools/set_ci_secrets.sh",
             sub(r"(not the one in the keystore.\" >&2\n)    exit 2\n", r"\1"),
             "credentials that cannot open the keystore would become CI secrets",
             'setup-scripts: set_ci_secrets.sh uploaded after a failed'),
    Mutation("setup", "a failed upload leaves the service account key on disk",
             "tools/setup_play_ci.sh",
             sub(r"^  trap cleanup_key EXIT INT TERM\n", "", flags=re.M),
             "a live Play key would be left in the secrets directory",
             'setup-scripts: setup_play_ci.sh left a service account key'),
    Mutation("setup", "setup_play_ci.sh accepts the wrong gcloud account",
             "tools/setup_play_ci.sh",
             sub(r"(Refusing.\" >&2\n)    exit 4\n", r"\1"),
             "Cloud resources would be created under the wrong Google account",
             'someone-else@example.com} was not refused'),

    # Play API -- play_scripts_test.dart
    Mutation("play", "play-api-check ignores a refused edit",
             ".github/workflows/play-api-check.yml",
             sub(r'if \[ "\$status" != "200" \]; then', "if false; then"),
             "a missing Console invite would print a green Play-access summary",
             'play-api-check: a 403 did not fail the check'),
    Mutation("play", "play-api-check accepts a foreign keystore",
             ".github/workflows/play-api-check.yml",
             sub(r'if \[ "\$bundle_fp" != "\$pem_fp" \]; then', "if false; then"),
             "a keystore secret for another key would pass the check",
             'play-api-check: a foreign keystore passed'),
    Mutation("play", "play_promote.sh allows production", "tools/play_promote.sh",
             chain(sub(r"internal \| alpha \| beta\) return 0",
                       "internal | alpha | beta | production) return 0"),
                   sub(r'    die_args "production is a human act[^\n]*\n', "    :\n")),
             "CI could promote a build to production",
             'play-promote: production was not refused'),
    Mutation("play", "play_promote.sh carries on after a refused promotion",
             "tools/play_promote.sh",
             sub(r'    die_api "the \'\$TO\' track refused the promotion, and not for the draft-app rule"',
                 "    :"),
             "a refused promotion would be reported as done",
             'play-promote: a refused promotion was reported as done'),

    # references -- references_test.dart
    Mutation("refs", "a comment cites a guard that does not exist", "tools/gate.sh",
             sub(r"^(set -euo pipefail)$",
                 # Split so this file does not itself name a missing file.
                 r"# Proven by test/guards/" "gate_proof_test" r".dart.\n\1",
                 flags=re.M),
             "a claim about a guard would stand with nothing behind it",
             'dangling-reference: 1 offender'),
    # The picker's path is split in these strings so this file does not
    # itself name a removed file (#92).
    Mutation("refs", "the ledger's removed path loses its exemption",
             "test/guards/references_test.dart",
             sub(r"\n  'lib/ui/game/temporary_new_game\.dart':\n[^\n]*\n", "\n"),
             "history naming a deleted file could no longer be told from a "
             "dangling claim, so the ledger would have to be rewritten",
             "dangling-reference .n8/decisions.md names lib/ui/game/"
             "temporary_new_game" ".dart"),
    Mutation("refs", "a code comment names the removed picker",
             "lib/ui/game/tool_row.dart",
             append("// temporary_new_game" ".dart\n"),
             "the ledger's exemption would reach every file, so a stale "
             "comment naming a deleted file would stand",
             "dangling-reference lib/ui/game/tool_row.dart names "
             "temporary_new_game" ".dart"),

    # rename -- rename_app_test.dart
    Mutation("rename", "rename_app.py skips the workflows", "tools/rename_app.py",
             sub(r"for path in PACKAGE_LITERAL_FILES \+ workflows:",
                 "for path in PACKAGE_LITERAL_FILES:"),
             "a renamed app would upload to Play under the template's id",
             'rename-app-leftover:'),
    Mutation("rename", "rename_app.py keeps the template-only workflow",
             "tools/rename_app.py",
             sub(r'^TEMPLATE_ONLY = \[[^\]]*\]', "TEMPLATE_ONLY = []", flags=re.M),
             "every app would run the template's smoke job",
             'rename-app-survivor:'),
    Mutation("rename", "rename_app.py writes past a file that no longer matches",
             "tools/rename_app.py",
             sub(r'raise Mismatch\(f"tools/check_aab\.sh does not name',
                 'print(f"tools/check_aab.sh does not name'),
             "a half-applied rename would leave the identity split across files",
             'rename-app-partial:'),

    # engine -- engine_purity_test.dart (#60)
    Mutation("engine", "an engine file imports Flutter", "lib/engine/square.dart",
             sub(r"^(/// A square of the board)",
                 r"import 'package:flutter/foundation.dart';\n\n\1", flags=re.M),
             "the engine could no longer run in a plain Dart isolate",
             'engine-purity: 1 offender'),
    Mutation("engine", "a nested engine file imports dart:io", "",
             None,
             "a file below lib/engine/ would escape a scan of the top level only",
             'engine-purity: 1 offender',
             adds=(("lib/engine/internal/io_probe.dart",
                    "import 'dart:io';\n\nFile? probe;\n"),)),

    # movegen -- test/engine/movegen_test.dart, test/guards/perft_test.dart (#61)
    Mutation("movegen", "castling through an attacked square is allowed",
             "lib/engine/src/board.dart",
             sub(r"!isAttacked\(crossed, by\) &&\s*", ""),
             "the king could castle across a square the opponent attacks",
             'movegen: castling through an attacked square'),
    Mutation("movegen", "en passant is allowed a move late",
             "lib/engine/src/board.dart",
             sub(r"\? \(from \+ to\) >> 1 : -1;", "? (from + to) >> 1 : enPassant;"),
             "a double push could be taken en passant after an intervening move",
             'movegen: en passant was offered a move late'),
    Mutation("movegen", "a pawn may promote to a king",
             "lib/engine/src/board.dart",
             sub(r"const _promotionKinds = \[queen, rook, bishop, knight\];",
                 "const _promotionKinds = [queen, rook, bishop, knight, king];"),
             "a pawn reaching the last rank could become a second king",
             'movegen: a pawn promoted to a king'),
    Mutation("movegen", "castling through an attacked square, seen by perft",
             "lib/engine/src/board.dart",
             sub(r"!isAttacked\(crossed, by\) &&\s*", ""),
             "the perft guard alone must also notice an illegal castle",
             'perft: kiwipete at depth',
             slow=True),

    # game status -- test/engine/game_status_test.dart (#63)
    Mutation("status", "a twofold repetition draws", "lib/engine/game_status.dart",
             sub(r"_occurrences\(history\) >= 3", "_occurrences(history) >= 2"),
             "the game would be drawn the second time a position appeared",
             'status: a twofold repetition ended the game'),
    Mutation("status", "the fifty-move draw fires a halfmove early",
             "lib/engine/game_status.dart",
             sub(r"current\.halfmoveClock >= 100", "current.halfmoveClock >= 99"),
             "a game would be drawn after 99 quiet halfmoves",
             'status: the fifty-move draw came before 100 halfmoves'),
    Mutation("status", "the fifty-move draw outranks a mate on the 100th halfmove",
             "lib/engine/game_status.dart",
             sub(r"(  final checked = inCheck\(current\);\n)",
                 r"\1  if (current.halfmoveClock >= 100) {\n"
                 r"    return const Draw(GameEndReason.fiftyMoves);\n  }\n"),
             "a mate delivered by the hundredth halfmove would be scored a draw (9.6.2)",
             'status: a mate on the hundredth halfmove was not a mate'),
    Mutation("status", "two knights count as insufficient material",
             "lib/engine/game_status.dart",
             sub(r"knights >= 2 \|\|", "knights >= 3 ||"),
             "K+N+N v K would be drawn although a mate is possible",
             'status: K+N+N v K was declared insufficient'),
    Mutation("status", "castling rights are ignored by position identity",
             "lib/engine/zobrist.dart",
             chain(sub(r"key \^= zobristKeys\[zobristCastling \+ bit\];",
                       "key ^= 0;"),
                   sub(r"a\.sideToMove != b\.sideToMove \|\| "
                       r"a\.castlingRights != b\.castlingRights",
                       "a.sideToMove != b.sideToMove")),
             "positions differing only in castling rights would count as a repetition (9.2.3.2)",
             'status: positions differing in castling rights counted'),
    Mutation("status", "a legal en-passant capture is ignored by position identity",
             "lib/engine/src/board.dart",
             sub(r"if \(enPassant < 0\) return _baseKey;", "return _baseKey;"),
             "a position with a legal en-passant capture would repeat one without (9.2.3.1)",
             'status: a legal en-passant capture did not split',
             also=(("lib/engine/zobrist.dart",
                    sub(r"return legalEnPassantFile\(a\) == legalEnPassantFile\(b\);",
                        "return true;")),)),
    Mutation("status", "any en-passant square splits a repetition",
             "lib/engine/zobrist.dart",
             sub(r"return legalEnPassantFile\(a\) == legalEnPassantFile\(b\);",
                 "return a.enPassant == b.enPassant;"),
             "a FEN en-passant square nobody can capture on would break a repetition (9.2.3.1)",
             'status: an en-passant square no legal capture can use'),
    Mutation("status", "make forgets to update the castling key",
             "lib/engine/src/board.dart",
             sub(r"(final rights = castling & _rightsKept\[from\] & _rightsKept\[to\];\n)"
                 r"\s*_baseKey \^= castlingKey\[castling\] \^ castlingKey\[rights\];\n",
                 r"\1"),
             "the incremental key would drift from the position, breaking repetition and the transposition table",
             'key: the incremental key differs from positionKey'),

    # game JSON -- test/engine/game_json_test.dart (#65)
    Mutation("game-json", "a saved game drops its clock", "lib/engine/game_json.dart",
             sub(r"\n\s*'clock': _clockToJson\(game, now\),", ""),
             "a restored game would lose both players' remaining time and every takeback's clock",
             'game-json: a saved game did not come back'),

    # search -- test/engine/search_test.dart (#66)
    Mutation("search", "the search chooses among pseudo-legal root moves",
             "lib/engine/search.dart",
             sub(r"_board\.legalMoves\(rootMoves\);",
                 "_board.pseudoLegalMoves(rootMoves);"),
             "the computer could play a move that leaves its own king in check (invariant 3)",
             'search-legal:',
             slow=True),
    Mutation("search", "the search reads a clock", "lib/engine/search.dart",
             sub(r"^(const int mateScore = 32000;)",
                 r"\1\n\nfinal searchClock = Stopwatch();", flags=re.M),
             "a search that reads the time could answer differently on another device (invariant 4)",
             'search-pure:'),

    # strength dial -- test/guards/strength_honesty_test.dart (#67)
    Mutation("strength", "noise added to Master", "lib/engine/strength.dart",
             sub(r"(nodeBudget: 1500000,\n\s*noiseCp: )0,", r"\g<1>30,"),
             "Master would hold something back while its description says nothing is (invariant 4)",
             'strength-honest:'),
    Mutation("strength", "Strong's depth changed without its text",
             "lib/engine/strength.dart",
             sub(r"depthCap: 5,", "depthCap: 4,"),
             "Strong would look four moves ahead while its description says five (invariant 4)",
             'strength-honest:'),
    Mutation("strength", "Beginner's mate-in-one handicap flipped",
             "lib/engine/strength.dart",
             sub(r"seesMateInOne: false,", "seesMateInOne: true,"),
             "Beginner would never miss a mate in one while its description says it will (invariant 4)",
             'strength-honest:'),
    Mutation("strength", "Master's choice goes through the noise",
             "lib/engine/strength.dart",
             chain(sub(r"case Found\(\) when !handicapped:",
                       "case Found() when !handicapped && step != Strength.master:"),
                   sub(r"score \+= rootNoise\(seed, key, root\.move, settings\.noiseCp\);",
                       "score += rootNoise(seed, key, root.move, max(settings.noiseCp, 30));")),
             "Master would play other than its own search's best move (invariant 4)",
             'strength-master: Master chose'),
    Mutation("strength", "the computer's table carries over between searches",
             "lib/engine/strength.dart",
             sub(r"Searcher\(table: table\?\.\.clear\(\)\)", "Searcher(table: table)"),
             "a move could depend on what the table held from an earlier search (invariant 4)",
             'strength-seed: the same position'),
    Mutation("strength", "the noise ignores the game's seed",
             "lib/engine/strength.dart",
             sub(r"splitMixFinalise\(seed \+ splitMixIncrement\)",
                 "splitMixFinalise(splitMixIncrement)"),
             "every game at a step would play alike, whatever its seed",
             'strength-seed: the seed never changed'),

    # computer player -- test/engine/computer_player_test.dart (#68)
    Mutation("computer", "the search runs inline in the caller's isolate",
             "lib/engine/computer_player.dart",
             sub(r"worker\.port\.send\(message\);", "_onReply(_serve(message));"),
             "the computer would think on the UI thread and freeze the app (invariant 4)",
             'computer-isolate: the search ran in the calling isolate'),
    Mutation("ci", "the weekly schedule is switched off (#69)",
             ".github/workflows/weekly.yml",
             sub(r'^  schedule:\n    - cron: "0 3 \* \* 0"[^\n]*\n', "", flags=re.M),
             "the strength ladder would be proven only when someone dispatches it",
             'weekly-cron: weekly.yml is not scheduled for Sunday 03:00 UTC'),
    Mutation("ci", "a workflow runs the Stockfish benchmark (#69)",
             ".github/workflows/weekly.yml",
             sub(r"(      - id: summary\n)",
                 "      - id: benchmark\n        name: Benchmark\n        run: tools/benchmark_stockfish.sh --games 1\n\n\\1"),
             "CI would install and run a dev-only engine benchmark for hours",
             'benchmark-not-ci: a workflow runs the dev-only Stockfish benchmark'),
    Mutation("ci", "the benchmark runs without Stockfish (#69)",
             "tools/benchmark_stockfish.sh",
             sub(r'if ! stockfish=\$\(command -v stockfish\); then\n(.*\n)*?fi\n',
                 'stockfish=$(command -v stockfish || true)\n'),
             "the benchmark could report a result it never played",
             'benchmark-refuses: without Stockfish the benchmark did not exit 3',
             slow=True),

    # platform surface -- test/guards/platform_surface_test.dart (#80, invariant 1)
    Mutation("platform-surface", "the store names a socket",
             "lib/data/app_store.dart",
             append("// Socket.connect(host, 80)\n"),
             "the device store could reach the network (invariant 1)",
             'platform-surface: network API in lib/'),
    Mutation("platform-surface", "the app scope names a socket",
             "lib/ui/app_scope.dart",
             append("// Socket.connect(host, 80)\n"),
             "UI code could reach the network (invariant 1)",
             'platform-surface: network API in lib/'),
    Mutation("platform-surface", "the activity names java.net",
             "android/app/src/main/kotlin/com/honestarcade/chess/MainActivity.kt",
             append('// java.net.URL("https://example.com")\n'),
             "the app's own Android bridge could reach the network (invariant 1)",
             'platform-surface: network API in MainActivity.kt'),
    Mutation("platform-surface", "the channel gains a fourth method",
             "android/app/src/main/kotlin/com/honestarcade/chess/MainActivity.kt",
             sub(r"^(\s*)(else -> result\.notImplemented\(\))",
                 r'\1"vibrate" -> result.success(null)\n\1\2', flags=re.M),
             "the bridge would carry a capability nobody reviewed (invariant 1)",
             'platform-surface: Kotlin channel branches'),
    Mutation("platform-surface", "the channel answers unknown methods",
             "android/app/src/main/kotlin/com/honestarcade/chess/MainActivity.kt",
             sub(r"else -> result\.notImplemented\(\)", "else -> result.success(null)"),
             "an unreviewed method name would get an answer instead of a refusal",
             'platform-surface: Kotlin channel branches'),
    Mutation("platform-surface", "the Kotlin channel name drifts",
             "android/app/src/main/kotlin/com/honestarcade/chess/MainActivity.kt",
             sub(r'CHANNEL = "honestchess/platform"', 'CHANNEL = "honestchess/platform2"'),
             "the guard's branch rule would read a channel Dart never calls",
             'platform-surface: channel name'),
    Mutation("platform-surface", "the Dart side invokes another method",
             "lib/platform/platform_channel.dart",
             sub(r"'appVersion'", "'appVersion2'"),
             "Dart would call a method the reviewed Kotlin side does not handle",
             'platform-surface: Dart channel methods'),
    Mutation("platform-surface", "the manifest turns backup off",
             "android/app/src/main/AndroidManifest.xml",
             sub(r"<application\n", '<application\n        android:allowBackup="false"\n'),
             "the app would opt out of the player's own backup, against the owner's decision",
             'platform-surface: backup attribute'),
    Mutation("platform-surface", "the manifest adds backup rules",
             "android/app/src/main/AndroidManifest.xml",
             sub(r"<application\n",
                 '<application\n        android:fullBackupContent="@xml/backup_rules"\n'),
             "backup rules could exclude the player's data from their own backup",
             'platform-surface: backup attribute'),
    Mutation("platform-surface", "the manifest adds data extraction rules",
             "android/app/src/main/AndroidManifest.xml",
             sub(r"<application\n",
                 '<application\n        android:dataExtractionRules="@xml/data_extraction_rules"\n'),
             "extraction rules could exclude the player's data from their own backup",
             'platform-surface: backup attribute'),
]


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def parses_as_yaml(path: pathlib.Path) -> bool:
    """A YAML mutation that breaks the syntax proves nothing."""
    if path.suffix not in {".yml", ".yaml"}:
        return True
    probe = run([
        "python3", "-c",
        "import sys\n"
        "try:\n"
        "    import yaml\n"
        "except ImportError:\n"
        "    sys.exit(3)\n"
        "yaml.safe_load(open(sys.argv[1]))\n",
        str(path),
    ])
    if probe.returncode == 3:
        return True  # no PyYAML here; the Dart guard will report a parse failure
    return probe.returncode == 0


def parses_as_shell(path: pathlib.Path) -> bool:
    """The shell half of the same rule: a mutation that leaves a script with a
    syntax error makes every test that runs it fail, whatever it asserts."""
    if path.suffix != ".sh":
        return True
    return run(["bash", "-n", str(path)]).returncode == 0


def compiles_as_dart(paths: list[pathlib.Path]) -> bool:
    """The Dart half of the rule `parses_as_yaml` states for YAML.

    A mutation that does not compile fails every test in the file at once,
    which is a red suite for a reason unrelated to the guard being measured.
    """
    dart = [p for p in paths if p.suffix == ".dart"]
    if not dart:
        return True
    probe = run(["dart", "analyze", "--no-fatal-warnings", *[str(p) for p in dart]])
    return probe.returncode == 0


def snapshot_bytes(paths: list) -> dict:
    """The current bytes of every path, so a binary mutation can be undone."""
    return {p: p.read_bytes() for p in paths}


def restore_bytes(snapshot: dict) -> None:
    """Puts every snapshotted file back, byte for byte, recreating a deleted
    one (and its directory)."""
    for p, data in snapshot.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)


def write_added(pairs: list) -> list:
    """Writes each `(path, text)` and returns what to remove afterwards: the
    files, then every directory created for them, deepest first."""
    made = []
    for path, text in pairs:
        missing_dirs = []
        parent = path.parent
        while not parent.exists():
            missing_dirs.append(parent)
            parent = parent.parent
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        made += [path, *missing_dirs]
    return made


def remove_added(made: list) -> None:
    for p in made:
        if p.is_dir():
            p.rmdir()
        else:
            p.unlink(missing_ok=True)


def self_test() -> int:
    """The binary round trip: a file deleted and a file overwritten both come
    back byte-identical from their snapshot."""
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        a, b = pathlib.Path(d) / "sub" / "a.bin", pathlib.Path(d) / "b.bin"
        a.parent.mkdir()
        a.write_bytes(bytes(range(256)))
        b.write_bytes(b"\x89PNG original")
        snap = snapshot_bytes([a, b])
        a.unlink()
        a.parent.rmdir()
        b.write_bytes(b"fixture bytes")
        restore_bytes(snap)
        ok = a.read_bytes() == bytes(range(256)) and b.read_bytes() == b"\x89PNG original"
        # adds: a file in new directories comes back out, directories and all.
        new = pathlib.Path(d) / "x" / "y" / "added.txt"
        made = write_added([(new, "added")])
        remove_added(made)
        ok = ok and not (pathlib.Path(d) / "x").exists()
    print("self-test: binary snapshot and added-file round trip "
          + ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--audit", action="store_true",
                    help="run the marker preflight alone and exit")
    ap.add_argument("--only", default="")
    ap.add_argument("--self-test", action="store_true",
                    help="prove the binary snapshot round trip and exit")
    args = ap.parse_args()
    if args.self_test:
        return self_test()

    selected = [m for m in MUTATIONS if args.only.lower() in
                f"{m.issue} {m.name} {m.path or m.deletes} "
                f"{' '.join(p for p, _ in m.adds)} "
                f"{' '.join(t for t, _ in m.replaces_with)}".lower()]

    if args.list:
        for m in selected:
            where = (m.path or m.deletes
                     or (m.replaces_with[0][0] if m.replaces_with else m.adds[0][0]))
            print(f"{m.issue:<7} {where:<42} {m.name}")
        print(f"\n{len(selected)} mutations")
        return 0

    # A run that dies between "write the mutation" and "restore the file"
    # leaves a defect in the working tree for the next commit to sweep up.
    # `finally` cannot cover a kill. A marker can: it outlives the process, so
    # an interrupted run is detectable by the next one instead of silent.
    if IN_FLIGHT.exists():
        print("mutation_check: a previous run did not restore these files:",
              file=sys.stderr)
        print(IN_FLIGHT.read_text().strip(), file=sys.stderr)
        print(f"Check them against HEAD (`git diff HEAD`) before committing "
              f"anything, then delete {IN_FLIGHT}", file=sys.stderr)
        return 2

    dirty = run(["git", "status", "--porcelain"]).stdout.strip()
    if dirty:
        print("mutation_check: refusing to run with uncommitted changes:", file=sys.stderr)
        print(dirty, file=sys.stderr)
        return 2

    # THE MARKERS, BEFORE ANY MUTATION.
    #
    # A verdict here is "the suite went red AND the marker is in its output".
    # A marker that appears in a GREEN run's output -- a test's name, what a
    # test prints, the runner's own text -- is present whatever happened, so
    # it would score `caught` for any red suite and could never report
    # WRONG-REASON. This audit refuses such markers before anything runs.
    #
    # Read from the json stream rather than the printed output, whose line
    # truncation depends on the checkout path, so the audit gives the same
    # verdict locally and in CI.
    #
    # The same run is the baseline: a suite that is red before any mutation
    # makes every verdict below meaningless.
    print("mutation_check: baseline and marker audit", flush=True)
    # SUITE_SLOW, the superset: a `slow`-tagged test's name and prints are in
    # the output of any run that includes it, so auditing the smaller suite
    # would leave them unchecked.
    base = run(SUITE_SLOW + ["--reporter", "json"])
    names: list[str] = []
    printed: list[str] = []
    suites: list[str] = []
    by_id: dict[str, str] = {}
    failed: list[str] = []
    for line in base.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get("type")
        if kind == "suite":
            # The PATH the runner prints before every test name: a marker
            # naming a test file would be present in every run.
            path = event.get("suite", {}).get("path", "")
            if path:
                suites.append(path)
        elif kind == "testStart":
            test = event.get("test", {})
            name = test.get("name", "")
            by_id[str(test.get("id"))] = name
            # `loading <path>` is the runner's own bookkeeping, not a test.
            if name and not name.startswith("loading "):
                names.append(name)
        elif kind == "print":
            # What a test PRINTS is in a green run's output exactly as a test
            # name is, so a marker matching it scores `caught` for any red
            # suite. A print can also depend on the machine, so a marker can
            # be vacuous in CI and fine locally: the remedy is a marker
            # distinctive enough that no message contains it, never a looser
            # check here.
            printed.append(event.get("message", ""))
        elif kind == "testDone" and event.get("result") != "success":
            failed.append(str(event.get("testID")))
    if base.returncode != 0:
        # The NAMES of what failed, which is what an operator can act on.
        print("mutation_check: the suite is RED before any mutation, so no "
              "verdict below would mean anything. Failing:", file=sys.stderr)
        for tid in failed or ["(none reported -- run the suite directly)"]:
            print(f"  {by_id.get(tid, tid)}", file=sys.stderr)
        return 2
    # A floor against the reporter yielding almost nothing -- the marker
    # audit below would then pass by reading nothing. `1` is deliberately not
    # a real accounting check. RAISE THIS as the guard suite grows, to a
    # number well below its real size: high enough to catch a reporter that
    # silently yields a fraction of the names, low enough to tolerate
    # ordinary run-to-run noise.
    MIN_EXPECTED_TEST_NAMES = 1
    if len(names) < MIN_EXPECTED_TEST_NAMES:
        print(f"mutation_check: the json reporter yielded {len(names)} test "
              f"names, fewer than the MIN_EXPECTED_TEST_NAMES floor of "
              f"{MIN_EXPECTED_TEST_NAMES} -- the marker audit below would "
              f"pass by reading nothing", file=sys.stderr)
        return 2
    # And every message a guard COULD print, from the source. What actually
    # prints can depend on the machine, so the audit reads the literals too
    # and gives the same verdict everywhere. Conservative by construction: it
    # may flag a marker that only MIGHT be printed, and the remedy for that is
    # a more distinctive marker, which always exists.
    printable: list[str] = []
    for source in sorted((ROOT / "test" / "guards").glob("*.dart")):
        text = source.read_text()
        # `printOnFailure` too: its text lands in the output exactly when the
        # suite is red, which is every run the battery judges. Both quote
        # styles, because Dart has two.
        for call in re.finditer(
                r"(?:print|printOnFailure|markTestSkipped)\(\s*(.*?)\);",
                text, re.S):
            printable.append(" ".join(
                re.findall(r"'([^']*)'|\"([^\"]*)\"", call.group(1))
                and [m[0] or m[1] for m in
                     re.findall(r"'([^']*)'|\"([^\"]*)\"", call.group(1))]
                or []))

    # And the runner's own chrome, which is in every run's output and in
    # none of the sources above: the file path before each name, the loading
    # lines, the counter and the closing line. The failure formatter's
    # vocabulary is included because the verdict is read from a RED run.
    #
    # Paths are compared RELATIVE to the repository root, so the verdict does
    # not depend on where the checkout lives.
    chrome = [str(pathlib.Path(p).relative_to(ROOT))
              if str(p).startswith(str(ROOT)) else str(p)
              for p in suites] + [
        # package:test's reporters
        "loading ",
        "All tests passed!",
        "Some tests failed.",
        "Skipped tests",
        # package:matcher's failure formatter, present in every red run
        "Expected:",
        "Actual:",
        "Which:",
        "package:matcher",
        "package:flutter_test",
        "Test failed. See exception logs above.",
        # the compact reporter's counter and clock
        "00:0",
        "+0",
        "-1",
    ]

    haystack = [("a test's NAME", n) for n in names]
    haystack += [("what a test PRINTS", t) for t in printed]
    haystack += [("a message a test can print", t) for t in printable]
    haystack += [("the runner's own output", t) for t in chrome]
    vacuous = [
        (m, kind, text)
        for m in selected
        if m.expect
        for kind, text in haystack
        if m.expect in text
    ]
    if vacuous:
        print("mutation_check: these markers are in the output of a GREEN "
              "run, so they are present whether or not the guard fired:",
              file=sys.stderr)
        for m, kind, text in vacuous:
            print(f"  {m.expect!r}  ({m.issue} {m.name})", file=sys.stderr)
            print(f"      matches {kind}: {text.strip()[:110]}", file=sys.stderr)
        print("Use a prefix of the assertion's own reason -- `leak:`, "
              "`overflow:` -- which nothing green prints.", file=sys.stderr)
        return 2
    if args.audit:
        print(f"{len(selected)} markers audited against {len(names)} test "
              f"names, {len(printed)} printed lines, {len(printable)} "
              f"messages a guard can print and {len(chrome)} lines the "
              f"runner itself emits; none of them matches")
        return 0

    print(f"mutation_check: {len(selected)} mutations\n")
    survived: list[Mutation] = []
    wrong: list[Mutation] = []
    broken: list[tuple[Mutation, str]] = []

    for i, m in enumerate(selected, 1):
        edits = [*([(m.path, m.apply)] if m.path else []), *m.also]
        targets = [ROOT / path for path, _ in edits]
        originals = [target.read_text() for target in targets]
        binary = [ROOT / m.deletes] if m.deletes else []
        binary += [ROOT / target for target, _ in m.replaces_with]
        label = f"[{i}/{len(selected)}] {m.issue} {m.name}"
        try:
            mutated = [apply(text) for (_, apply), text in zip(edits, originals)]
        except LookupError as exc:
            broken.append((m, str(exc)))
            print(f"  BROKEN  {label}\n          {exc}")
            continue
        new_files = [(ROOT / path, text) for path, text in m.adds]
        present = [p for p, _ in new_files if p.exists()]
        if present:
            broken.append((m, f"file to add already exists: {present[0]}"))
            print(f"  BROKEN  {label}\n          {present[0]} already exists")
            continue
        missing = [p for p in binary if not p.exists()]
        if missing:
            broken.append((m, f"binary target missing: {missing[0]}"))
            print(f"  BROKEN  {label}\n          {missing[0]} does not exist")
            continue
        fixtures = {ROOT / target: (ROOT / fixture).read_bytes()
                    for target, fixture in m.replaces_with}
        same = [p for p, data in fixtures.items() if p.read_bytes() == data]
        if (mutated == originals and not binary and not new_files) or same:
            broken.append((m, "changed nothing"))
            print(f"  BROKEN  {label}\n          changed nothing")
            continue

        # The third source of a vacuous marker, and the one no baseline run
        # can show: the mutation's OWN inserted text. A guard that prints the
        # offending line puts that text into the output, so a marker matching
        # it is present because the mutation ran, not because the guard fired.
        if m.expect:
            added = "\n".join(
                line
                for new, old in zip(mutated, originals)
                for line in new.splitlines()
                if line not in old.splitlines()
            ) + "\n" + "\n".join(text for _, text in new_files)
            if m.expect in added:
                broken.append((m, "the marker is in the text this mutation "
                                  "inserts, so a guard that echoes the "
                                  "offending line satisfies it"))
                print(f"  BROKEN  {label}\n          marker {m.expect!r} is in "
                      f"this mutation's own inserted text")
                continue

        IN_FLIGHT.write_text(
            f"{m.issue} {m.name}\n"
            + "".join(f"  {path}\n" for path, _ in edits)
            + "".join(f"  {p.relative_to(ROOT)}\n" for p in binary)
            + "".join(f"  {p.relative_to(ROOT)} (added)\n" for p, _ in new_files)
        )
        snapshot = snapshot_bytes(binary)
        for target, text in zip(targets, mutated):
            target.write_text(text)
        if m.deletes:
            (ROOT / m.deletes).unlink()
        for target, data in fixtures.items():
            target.write_bytes(data)
        made = write_added(new_files)
        try:
            unparseable = [t for t in targets
                           if not (parses_as_yaml(t) and parses_as_shell(t))]
            if unparseable:
                broken.append((m, "left the file unparseable — it would fail for the wrong reason"))
                print(f"  BROKEN  {label}\n          unparseable after mutation")
                continue
            if not compiles_as_dart(targets):
                broken.append((m, "left the Dart unanalyzable — it would fail for the wrong reason"))
                print(f"  BROKEN  {label}\n          does not compile after mutation")
                continue
            suite = SUITE_SLOW if m.slow else SUITE
            result = run(suite)
            output = result.stdout + result.stderr
            if result.returncode == 0:
                # Re-run before reporting a survivor. A SURVIVED verdict says
                # a guard has a hole, and one flaky green would announce a
                # hole that is not there. A second green costs one suite run,
                # on the rare path only.
                confirm = run(suite)
                if confirm.returncode != 0:
                    output = confirm.stdout + confirm.stderr
                    print(f"  (first run of {label} was green, second was not "
                          f"— reporting the second)")
                else:
                    survived.append(m)
                    print(f"  SURVIVED {label}\n           {m.why}")
            if result.returncode == 0 and m not in survived:
                # Fell through from the flaky branch above; judged on the
                # confirming run's output.
                if m.expect and m.expect not in output:
                    wrong.append(m)
                    print(f"  WRONG-REASON {label}\n               the suite "
                          f"failed, but not with {m.expect!r}")
                else:
                    print(f"  caught  {label}")
            elif result.returncode == 0:
                pass
            elif m.expect and m.expect not in output:
                # Red, but not for this reason. Counting it as caught is how a
                # guard gets credit for an assertion it does not make.
                wrong.append(m)
                print(f"  WRONG-REASON {label}\n               the suite failed, "
                      f"but not with {m.expect!r}")
            else:
                print(f"  caught  {label}")
        finally:
            for target, text in zip(targets, originals):
                target.write_text(text)
            restore_bytes(snapshot)
            remove_added(made)
            for created in m.creates:
                (ROOT / created).unlink(missing_ok=True)
            IN_FLIGHT.unlink(missing_ok=True)

    print()
    if broken:
        print(f"{len(broken)} mutation(s) could not be applied — the battery is "
              f"testing less than it claims:", file=sys.stderr)
        for m, why in broken:
            print(f"  {m.issue} {m.name}: {why}", file=sys.stderr)
    if wrong:
        print(f"{len(wrong)} mutation(s) failed the suite for the WRONG REASON — "
              f"the named assertion did not fire:", file=sys.stderr)
        for m in wrong:
            print(f"  {m.issue} {m.path}: {m.name} (expected {m.expect!r})",
                  file=sys.stderr)
    if survived:
        print(f"{len(survived)} mutation(s) SURVIVED — the guards do not catch them:",
              file=sys.stderr)
        for m in survived:
            print(f"  {m.issue} {m.path}: {m.name}", file=sys.stderr)
    if broken or survived or wrong:
        return 1 if (survived or wrong) else 2
    print(f"all {len(selected)} mutations caught")
    return 0


if __name__ == "__main__":
    sys.exit(main())
