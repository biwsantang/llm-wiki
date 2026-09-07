#!/usr/bin/env python3
"""Validate and migrate LLM Wiki bundles to Open Knowledge Format v0.2.

This tool intentionally implements the small interoperability surface of the
OKF specification.  LLM Wiki-specific concepts are represented with regular
OKF `type` values and optional metadata beneath `llm_wiki`, never by changing
the base format.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import yaml
except ModuleNotFoundError:  # pragma: no cover - exercised by the CLI user
    print("llm-wiki OKF support requires PyYAML: python3 -m pip install pyyaml", file=sys.stderr)
    raise SystemExit(2)


OKF_VERSION = "0.2"
RESERVED = {"index.md", "log.md"}
RUNTIME_PARTS = {".sessions", ".librarian", ".audit", ".obsidian", "inbox"}
LEGACY_EXTENSION_KEYS = {
    "category",
    "kind",
    "view",
    "filters",
    "dataset_id",
    "storage",
    "locations",
    "formats",
    "schema_status",
    "priority",
    "next_action",
    "aliases",
    "confidence",
    "volatility",
    "compiled-from",
    "origin",
    "inventory",
    "project",
    "related_wikis",
}


@dataclass(frozen=True)
class Issue:
    path: Path
    message: str


def parse_markdown(path: Path) -> tuple[dict[str, Any] | None, str]:
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return None, text
    closing = re.search(r"(?m)^---\s*$", text[4:])
    if not closing:
        raise ValueError("unterminated YAML frontmatter")
    end = 4 + closing.start()
    raw = text[4:end]
    value = yaml.safe_load(raw) or {}
    if not isinstance(value, dict):
        raise ValueError("frontmatter must be a YAML mapping")
    return value, text[4 + closing.end() :].lstrip("\n")


def serialize(frontmatter: dict[str, Any], body: str) -> str:
    yaml_text = yaml.safe_dump(frontmatter, sort_keys=False, allow_unicode=True).rstrip()
    return f"---\n{yaml_text}\n---\n\n{body.lstrip()}"


def is_runtime_path(root: Path, path: Path) -> bool:
    return any(part in RUNTIME_PARTS for part in path.relative_to(root).parts)


def markdown_files(root: Path) -> list[Path]:
    return sorted(path for path in root.rglob("*.md") if not is_runtime_path(root, path))


def iso8601(value: Any) -> str | None:
    if isinstance(value, dt.datetime):
        parsed = value
    elif isinstance(value, dt.date):
        parsed = dt.datetime.combine(value, dt.time.min, tzinfo=dt.timezone.utc)
    elif isinstance(value, str):
        try:
            parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            try:
                parsed = dt.datetime.combine(dt.date.fromisoformat(value), dt.time.min, tzinfo=dt.timezone.utc)
            except ValueError:
                return None
    else:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.isoformat(timespec="seconds").replace("+00:00", "Z")


def require_event(value: Any, field: str, path: Path, issues: list[Issue]) -> None:
    events = value if isinstance(value, list) else [value]
    for event in events:
        if not isinstance(event, dict) or not event.get("by") or not iso8601(event.get("at")):
            issues.append(Issue(path, f"{field} entries require non-empty by and ISO-8601 at values"))


def validate_log(path: Path, text: str, issues: list[Issue]) -> None:
    dates = re.findall(r"(?m)^##\s+(\S+)\s*$", text)
    if not dates and text.strip():
        issues.append(Issue(path, "log.md must contain ISO-8601 date headings"))
        return
    if any(not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) for value in dates):
        issues.append(Issue(path, "log.md headings must be exactly ## YYYY-MM-DD"))
    if dates != sorted(dates, reverse=True):
        issues.append(Issue(path, "log.md entries must be newest first"))


def validate(root: Path) -> list[Issue]:
    issues: list[Issue] = []
    root_index = root / "index.md"
    if root_index.exists():
        try:
            frontmatter, _ = parse_markdown(root_index)
        except (OSError, UnicodeError, ValueError, yaml.YAMLError) as error:
            issues.append(Issue(root_index, str(error)))
        else:
            if frontmatter and set(frontmatter) != {"okf_version"}:
                issues.append(Issue(root_index, "root index.md may contain only okf_version frontmatter"))
            if frontmatter and str(frontmatter.get("okf_version")) != OKF_VERSION:
                issues.append(Issue(root_index, "root index.md okf_version must be 0.2"))

    for path in markdown_files(root):
        if path.name == "log.md":
            validate_log(path, path.read_text(encoding="utf-8"), issues)
            continue
        try:
            frontmatter, _ = parse_markdown(path)
        except (OSError, UnicodeError, ValueError, yaml.YAMLError) as error:
            issues.append(Issue(path, str(error)))
            continue
        if path.name == "index.md":
            if frontmatter and path != root_index:
                issues.append(Issue(path, "only the bundle-root index.md may have frontmatter"))
            continue
        if frontmatter is None:
            issues.append(Issue(path, "non-reserved Markdown files require YAML frontmatter"))
            continue
        if not isinstance(frontmatter.get("type"), str) or not frontmatter["type"].strip():
            issues.append(Issue(path, "non-reserved Markdown files require a non-empty type"))
        if "sources" in frontmatter:
            sources = frontmatter["sources"]
            if not isinstance(sources, list) or any(not isinstance(item, dict) or not item.get("resource") for item in sources):
                issues.append(Issue(path, "sources must be a list of mappings with resource"))
        if "generated" in frontmatter:
            require_event(frontmatter["generated"], "generated", path, issues)
        if "verified" in frontmatter:
            require_event(frontmatter["verified"], "verified", path, issues)
        if "stale_after" in frontmatter and not iso8601(frontmatter["stale_after"]):
            issues.append(Issue(path, "stale_after must be an ISO-8601 datetime with UTC offset"))
    return issues


def legacy_type(relative: Path, frontmatter: dict[str, Any]) -> str:
    parts = relative.parts
    if relative.name == "config.md":
        return "Bundle Configuration"
    if relative.name == "schema.md":
        return "Topic Guide"
    if relative.name == "MANIFEST.md":
        return "Dataset Manifest"
    if relative.name == "WHY.md":
        return "Project Rationale"
    if relative.name == "BRIEF.md":
        return "Project Brief"
    if parts and parts[0] == "raw":
        return {
            "articles": "Source Article", "papers": "Source Paper", "repos": "Source Repository",
            "notes": "Source Note", "data": "Source Data",
        }.get(parts[1] if len(parts) > 1 else "", "Source")
    if parts and parts[0] == "wiki":
        return {"concepts": "Concept", "topics": "Topic", "references": "Reference", "theses": "Thesis"}.get(
            parts[1] if len(parts) > 1 else "", "Knowledge")
    if parts and parts[0] == "inventory":
        return {
            "items": "Inventory Item", "ideas": "Idea", "candidates": "Ingest Candidate",
            "entities": "Entity", "corpora": "Corpus", "views": "Inventory View",
        }.get(parts[1] if len(parts) > 1 else "", "Inventory Record")
    if parts and parts[0] == "datasets":
        return "Dataset Artifact"
    if parts and parts[0] == "output":
        return "Collection" if frontmatter.get("type") == "collection" else "Report"
    return "Document"


def remap_path(value: str) -> str:
    value = value.replace("\\", "/").replace("_index.md", "index.md")
    if value.startswith(("http://", "https://", "/")):
        return value
    return f"/{value}"


def migrate_frontmatter(relative: Path, frontmatter: dict[str, Any]) -> dict[str, Any]:
    original = dict(frontmatter)
    result: dict[str, Any] = {}
    result["type"] = legacy_type(relative, original)
    for key in ("title", "description", "resource", "tags", "status", "stale_after"):
        if key in original:
            result[key] = original[key]
    if "source" in original and "resource" not in result:
        result["resource"] = original["source"]
    sources = original.get("sources")
    if isinstance(sources, list):
        converted: list[dict[str, Any]] = []
        for source in sources:
            if isinstance(source, str):
                converted.append({"resource": remap_path(source)})
            elif isinstance(source, dict) and source.get("resource"):
                converted.append({**source, "resource": remap_path(str(source["resource"]))})
        if converted:
            result["sources"] = converted
    generated = original.get("generated")
    if isinstance(generated, dict) and generated.get("by") and iso8601(generated.get("at")):
        result["generated"] = {"by": str(generated["by"]), "at": iso8601(generated["at"])}
    else:
        legacy_time = next((original[key] for key in ("updated", "ingested", "created") if key in original and iso8601(original[key])), None)
        result["generated"] = {"by": "process:llm-wiki-migrator", "at": iso8601(legacy_time) or "1970-01-01T00:00:00Z"}
    verified = original.get("verified")
    if isinstance(verified, (str, dt.date, dt.datetime)) and iso8601(verified):
        result["verified"] = [{"by": "process:llm-wiki-legacy", "at": iso8601(verified)}]
    elif isinstance(verified, (dict, list)):
        result["verified"] = verified
    extension = {key: original[key] for key in LEGACY_EXTENSION_KEYS if key in original}
    legacy_dates = {key: str(original[key]) for key in ("created", "updated", "ingested") if key in original}
    if legacy_dates:
        extension["legacy_dates"] = legacy_dates
    if extension:
        result["llm_wiki"] = extension
    return result


def convert_log(text: str) -> str:
    groups: dict[str, list[str]] = {}
    legacy = re.findall(r"(?m)^## \[(\d{4}-\d{2}-\d{2})\]\s*([^|\n]+?)\s*\|\s*(.+)$", text)
    if legacy:
        for date, operation, description in legacy:
            groups.setdefault(date, []).append(f"* **{operation.strip().title()}**: {description.strip()}")
    else:
        current_date: str | None = None
        for line in text.splitlines():
            heading = re.fullmatch(r"##\s+(\d{4}-\d{2}-\d{2})", line)
            if heading:
                current_date = heading.group(1)
                groups.setdefault(current_date, [])
            elif current_date and line.strip():
                groups[current_date].append(line)
    lines = ["# Directory Update Log", ""]
    for date in sorted(groups, reverse=True):
        lines.extend([f"## {date}", *groups[date], ""])
    return "\n".join(lines).rstrip() + "\n"


def copy_and_migrate(source: Path, target: Path) -> list[str]:
    if target.exists() and any(target.iterdir()):
        raise ValueError(f"target already exists and is not empty: {target}")
    target.mkdir(parents=True, exist_ok=True)
    skipped: list[str] = []
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        if is_runtime_path(source, path):
            if path.is_file():
                skipped.append(relative.as_posix())
            continue
        destination_relative = Path(*("index.md" if part == "_index.md" else part for part in relative.parts))
        destination = target / destination_relative
        if path.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        if path.suffix.lower() != ".md":
            shutil.copy2(path, destination)
            continue
        frontmatter, body = parse_markdown(path)
        body = body.replace("_index.md", "index.md")
        if destination.name == "index.md":
            if destination == target / "index.md":
                destination.write_text(serialize({"okf_version": OKF_VERSION}, body), encoding="utf-8")
            else:
                destination.write_text(body.lstrip(), encoding="utf-8")
        elif destination.name == "log.md":
            destination.write_text(convert_log(path.read_text(encoding="utf-8")), encoding="utf-8")
        else:
            destination.write_text(serialize(migrate_frontmatter(destination_relative, frontmatter or {}), body), encoding="utf-8")
    return skipped


def command_validate(args: argparse.Namespace) -> int:
    root = Path(args.bundle).resolve()
    issues = validate(root)
    if issues:
        for issue in issues:
            print(f"ERROR {issue.path.relative_to(root)}: {issue.message}")
        print(f"Result: FAIL ({len(issues)} errors)")
        return 1
    print(f"Result: PASS (OKF v{OKF_VERSION})")
    return 0


def command_migrate(args: argparse.Namespace) -> int:
    source = Path(args.source).resolve()
    target = Path(args.target).resolve()
    if not source.is_dir():
        raise SystemExit(f"source bundle does not exist: {source}")
    if args.dry_run:
        legacy_indexes = len(list(source.rglob("_index.md")))
        markdown = len(markdown_files(source))
        print(f"Would migrate {markdown} Markdown files and rename {legacy_indexes} _index.md files.")
        print(f"Source: {source}\nTarget: {target}")
        return 0
    skipped = copy_and_migrate(source, target)
    issues = validate(target)
    if issues:
        for issue in issues:
            print(f"ERROR {issue.path.relative_to(target)}: {issue.message}")
        print("Migration wrote an invalid bundle; inspect the target and do not use it as OKF.")
        return 1
    print(f"Migrated to {target}")
    if skipped:
        print(f"Skipped {len(skipped)} operational files outside the OKF bundle boundary.")
    print(f"Result: PASS (OKF v{OKF_VERSION})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="LLM Wiki Open Knowledge Format v0.2 tools")
    commands = parser.add_subparsers(dest="command", required=True)
    validate_parser = commands.add_parser("validate", help="Validate an OKF v0.2 bundle")
    validate_parser.add_argument("bundle")
    validate_parser.set_defaults(handler=command_validate)
    migrate_parser = commands.add_parser("migrate", help="Convert a legacy LLM Wiki to a new OKF bundle")
    migrate_parser.add_argument("source")
    migrate_parser.add_argument("target")
    migrate_parser.add_argument("--dry-run", action="store_true")
    migrate_parser.set_defaults(handler=command_migrate)
    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
