#!/usr/bin/env python3
"""Give the app its identity: rewrite app_identity.yaml and every file that
repeats a value from it.

Usage:
  tools/rename_app.py <package-id> "<Launcher Label>"
      [--dart-package NAME] [--slug SLUG] [--min-sdk N]
      [--orientation portrait|landscape|any]

  --dart-package  defaults to the label in snake_case ("Honest Solitaire"
                  -> honest_solitaire)
  --slug          defaults to the last segment of the package id; used for
                  keystore file names and the Cloud project <slug>-ci
  --min-sdk, --orientation  default to the current app_identity.yaml values

The old values are read from app_identity.yaml, so the script can be run
again to change them. Every edit is computed before anything is written: if
one file no longer contains what the identity file says it should, nothing
changes and the script names the file.

test/guards/android_identity_test.dart asserts the result.

Exit: 0 renamed, 1 a file did not match, 2 bad arguments.
"""
from __future__ import annotations

import argparse
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
IDENTITY = ROOT / "app_identity.yaml"
GRADLE = "android/app/build.gradle.kts"
MANIFEST = "android/app/src/main/AndroidManifest.xml"
KOTLIN_ROOT = "android/app/src/main/kotlin"
PUBSPEC = "pubspec.yaml"
# Files that name the package id as a literal.
PACKAGE_LITERAL_FILES = ["tools/check_aab.sh"]
SLUG_FILES = ["tools/make_upload_key.sh", "tools/setup_play_ci.sh",
              "tools/set_ci_secrets.sh"]
LABEL_FILES = ["tools/make_upload_key.sh", "tools/setup_play_ci.sh"]
# Exists only in the template repository; the rename deletes it from an app.
TEMPLATE_ONLY = [".github/workflows/template-smoke.yml"]

PACKAGE_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$")
DART_RE = re.compile(r"^[a-z][a-z0-9_]*$")
# The Cloud project id is `<slug>-ci`: 6 to 30 characters, lower-case letters,
# digits and hyphens, starting with a letter.
SLUG_RE = re.compile(r"^[a-z][a-z0-9-]{3,26}$")
ORIENTATIONS = ("portrait", "landscape", "any")
# A label is pasted into XML attributes and double-quoted shell defaults.
LABEL_FORBIDDEN = set('"\'\\$`}<>&')
DART_RESERVED = {
    "abstract", "as", "assert", "async", "await", "break", "case", "catch",
    "class", "const", "continue", "default", "deferred", "do", "dynamic",
    "else", "enum", "export", "extends", "extension", "external", "factory",
    "false", "final", "finally", "for", "function", "get", "if", "implements",
    "import", "in", "interface", "is", "late", "library", "mixin", "new",
    "null", "on", "operator", "part", "required", "rethrow", "return", "set",
    "show", "static", "super", "switch", "sync", "this", "throw", "true",
    "try", "typedef", "var", "void", "while", "with", "yield",
    # Package names the SDK already uses.
    "flutter", "flutter_test", "test", "yaml",
}

# A package segment that is a keyword cannot be written in a Kotlin or Java
# `package` line.
JAVA_KEYWORDS = {
    "abstract", "as", "assert", "boolean", "break", "byte", "case", "catch",
    "char", "class", "const", "continue", "default", "do", "double", "else",
    "enum", "extends", "false", "final", "finally", "float", "for", "fun",
    "goto", "if", "implements", "import", "in", "instanceof", "int",
    "interface", "is", "long", "native", "new", "null", "object", "package",
    "private", "protected", "public", "return", "short", "static", "super",
    "switch", "synchronized", "this", "throw", "throws", "transient", "true",
    "try", "typealias", "typeof", "val", "var", "void", "volatile", "when",
    "while",
}


class Mismatch(Exception):
    pass


def read_identity() -> dict:
    """The flat `key: value` shape app_identity.yaml has. Not a YAML parser:
    the guard reads the same file with package:yaml, so a shape this cannot
    read fails there too."""
    values = {}
    for line in IDENTITY.read_text().splitlines():
        line = re.sub(r"\s+#.*$", "", line)
        m = re.match(r"^([a-z_]+):\s*(.*?)\s*$", line)
        if m:
            values[m.group(1)] = m.group(2)
    missing = {"package_id", "label", "dart_package", "slug", "min_sdk",
               "orientation"} - values.keys()
    if missing:
        raise Mismatch(f"app_identity.yaml is missing {sorted(missing)}")
    return values


def snake(label: str) -> str:
    name = re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")
    if name and name[0].isdigit():
        name = "app_" + name
    return name


def validate(new: dict) -> list[str]:
    errors = []
    pid = new["package_id"]
    if not PACKAGE_RE.match(pid):
        errors.append(f"package id {pid!r} is not lower-case dotted segments, "
                      "each starting with a letter")
    elif pid.startswith("com.example."):
        errors.append("Play refuses com.example.* package ids")
    if any(seg in JAVA_KEYWORDS for seg in pid.split(".")):
        errors.append(f"package id {pid!r} has a Kotlin/Java keyword segment")
    label = new["label"]
    if not label.strip() or LABEL_FORBIDDEN & set(label):
        errors.append(f"label {label!r} is empty or contains one of "
                      f"{''.join(sorted(LABEL_FORBIDDEN))}")
    dart = new["dart_package"]
    if not DART_RE.match(dart) or dart in DART_RESERVED:
        errors.append(f"Dart package {dart!r} is not a valid, unreserved "
                      "lower_snake_case name (pass --dart-package)")
    if not SLUG_RE.match(new["slug"]):
        errors.append(f"slug {new['slug']!r} must be 4-27 lower-case letters, "
                      "digits or hyphens, starting with a letter (pass --slug)")
    if not re.fullmatch(r"\d+", new["min_sdk"]) or not 21 <= int(new["min_sdk"]) <= 40:
        errors.append(f"min SDK {new['min_sdk']!r} is not between 21 and 40")
    if new["orientation"] not in ORIENTATIONS:
        errors.append(f"orientation {new['orientation']!r} is not one of "
                      f"{', '.join(ORIENTATIONS)}")
    return errors


def sub_once(path: str, text: str, pattern: str, repl, flags=0) -> str:
    out, n = re.subn(pattern, repl, text, flags=flags)
    if n != 1:
        raise Mismatch(f"{path}: expected exactly one match for {pattern!r}, "
                       f"found {n}")
    return out


def package_token(pid: str) -> str:
    """The id as a whole token: not a prefix of a longer id."""
    return r"(?<![A-Za-z0-9_.])" + re.escape(pid) + r"(?![A-Za-z0-9_])"


def plan(old: dict, new: dict) -> dict[str, str]:
    """Every file's new text, keyed by repository-relative path."""
    edits: dict[str, str] = {}

    def text(path: str) -> str:
        return edits.get(path) or (ROOT / path).read_text()

    g = text(GRADLE)
    g = sub_once(GRADLE, g, r'(\bnamespace = )"[^"]*"',
                 lambda m: f'{m.group(1)}"{new["package_id"]}"')
    g = sub_once(GRADLE, g, r'(\bapplicationId = )"[^"]*"',
                 lambda m: f'{m.group(1)}"{new["package_id"]}"')
    g = sub_once(GRADLE, g, r"(\bminSdk = )\d+",
                 lambda m: f"{m.group(1)}{new['min_sdk']}")
    edits[GRADLE] = g

    m = text(MANIFEST)
    m = sub_once(MANIFEST, m, r'(<application\b[^>]*?android:label=")[^"]*"',
                 lambda x: f'{x.group(1)}{new["label"]}"', flags=re.S)
    lock = r'(android:screenOrientation=")[^"]*"'
    if new["orientation"] == "any":
        m = re.sub(r'\n[ \t]*' + lock, "", m)
    elif re.search(lock, m):
        m = sub_once(MANIFEST, m, lock,
                     lambda x: f'{x.group(1)}{new["orientation"]}"')
    else:
        m = sub_once(MANIFEST, m,
                     r'(\n([ \t]*)android:name="\.MainActivity")',
                     lambda x: f'{x.group(1)}\n{x.group(2)}'
                               f'android:screenOrientation="{new["orientation"]}"')
    edits[MANIFEST] = m

    edits[PUBSPEC] = sub_once(PUBSPEC, text(PUBSPEC), r"^name: \S+$",
                              f"name: {new['dart_package']}", flags=re.M)
    old_import = f"package:{old['dart_package']}/"
    for dart in sorted([*ROOT.glob("lib/**/*.dart"), *ROOT.glob("test/**/*.dart")]):
        rel = str(dart.relative_to(ROOT))
        src = text(rel)
        if old_import in src:
            edits[rel] = src.replace(old_import, f"package:{new['dart_package']}/")

    workflows = sorted(str(p.relative_to(ROOT))
                       for p in (ROOT / ".github/workflows").glob("*.yml"))
    for path in PACKAGE_LITERAL_FILES + workflows:
        src = text(path)
        out = re.sub(package_token(old["package_id"]), new["package_id"], src)
        if out != src:
            edits[path] = out
    if old["package_id"] != new["package_id"] and "tools/check_aab.sh" not in edits:
        raise Mismatch(f"tools/check_aab.sh does not name {old['package_id']}")

    for path in SLUG_FILES:
        edits[path] = sub_once(path, text(path),
                               r'(APP_SLUG="\$\{HS_APP_SLUG:-)[^}]*\}"',
                               lambda x: f'{x.group(1)}{new["slug"]}}}"')
    for path in LABEL_FILES:
        edits[path] = sub_once(path, text(path),
                               r'(APP_DISPLAY_NAME="\$\{HS_APP_DISPLAY_NAME:-)[^}]*\}"',
                               lambda x: f'{x.group(1)}{new["label"]}}}"')

    ident = IDENTITY.read_text()
    for key in ("package_id", "label", "dart_package", "slug", "min_sdk",
                "orientation"):
        ident = sub_once("app_identity.yaml", ident,
                         rf"^({key}:[ \t]*)[^#\n]*?([ \t]*(#.*)?)$",
                         lambda x, k=key: f"{x.group(1)}{new[k]}{x.group(2)}",
                         flags=re.M)
    edits["app_identity.yaml"] = ident
    return edits


def kotlin_dir(pid: str) -> pathlib.Path:
    return ROOT / KOTLIN_ROOT / pathlib.Path(*pid.split("."))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("package_id")
    ap.add_argument("label")
    ap.add_argument("--dart-package")
    ap.add_argument("--slug")
    ap.add_argument("--min-sdk")
    ap.add_argument("--orientation", choices=ORIENTATIONS)
    args = ap.parse_args()

    try:
        old = read_identity()
    except Mismatch as exc:
        print(f"rename_app: {exc}", file=sys.stderr)
        return 1
    new = {
        "package_id": args.package_id,
        "label": args.label,
        "dart_package": args.dart_package or snake(args.label),
        "slug": args.slug or args.package_id.rsplit(".", 1)[-1].replace("_", "-"),
        "min_sdk": args.min_sdk or old["min_sdk"],
        "orientation": args.orientation or old["orientation"],
    }
    errors = validate(new)
    if errors:
        for e in errors:
            print(f"rename_app: {e}", file=sys.stderr)
        return 2

    old_kt = kotlin_dir(old["package_id"]) / "MainActivity.kt"
    if not old_kt.exists():
        print(f"rename_app: {old_kt.relative_to(ROOT)} does not exist; "
              "app_identity.yaml no longer matches the Kotlin sources",
              file=sys.stderr)
        return 1
    try:
        edits = plan(old, new)
        kt = sub_once(str(old_kt.relative_to(ROOT)), old_kt.read_text(),
                      r"^package \S+$", f"package {new['package_id']}",
                      flags=re.M)
    except Mismatch as exc:
        print(f"rename_app: {exc}; nothing was changed", file=sys.stderr)
        return 1

    for path, content in edits.items():
        (ROOT / path).write_text(content)
    old_kt.write_text(kt)
    new_dir = kotlin_dir(new["package_id"])
    if new_dir != old_kt.parent:
        new_dir.mkdir(parents=True, exist_ok=True)
        for f in old_kt.parent.iterdir():
            shutil.move(str(f), str(new_dir / f.name))
        d = old_kt.parent
        while d != ROOT / KOTLIN_ROOT and not any(d.iterdir()):
            d.rmdir()
            d = d.parent
    for path in TEMPLATE_ONLY:
        (ROOT / path).unlink(missing_ok=True)

    print(f"renamed to {new['package_id']} \"{new['label']}\" "
          f"(Dart package {new['dart_package']}, slug {new['slug']}, "
          f"minSdk {new['min_sdk']}, orientation {new['orientation']})")
    print("next: flutter pub get && tools/gate.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
