# OKF v0.2 Output Profile

New LLM Wiki topic wikis are [Open Knowledge Format (OKF) v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
bundles. This profile adds LLM Wiki workflow metadata without changing the OKF
interoperability surface.

## Non-negotiable rules

1. Each topic wiki is one bundle. The hub registry, session captures, and
   caches are operational state, not bundle concepts.
2. The only reserved Markdown filenames are `index.md` and `log.md`. Never
   create `_index.md` in a new bundle.
3. Every other `.md` file starts with parseable YAML frontmatter and has a
   non-empty, descriptive `type`.
4. `index.md` files contain no frontmatter, except the bundle-root index may
   contain only `okf_version: "0.2"`.
5. `log.md` uses `## YYYY-MM-DD` headings, newest first, followed by prose
   list entries.
6. Use standard Markdown links. Obsidian wikilinks may appear alongside them
   as optional presentation syntax, never instead of a Markdown link.

## Layout

The existing folders are valid OKF organization choices and remain in use:

```text
<topic-bundle>/
  index.md
  log.md
  config.md
  schema.md
  raw/{articles,papers,repos,notes,data}/
  wiki/{concepts,topics,references,theses}/
  inventory/{items,ideas,candidates,entities,corpora,views}/
  datasets/<slug>/
  output/
```

Every existing managed directory gets `index.md`; optional directories receive
one only after that directory exists. Hidden operational directories such as
`.sessions/`, `.audit/`, `.librarian/`, and `inbox/` are outside the exported
bundle boundary and must not be included when validating or packaging a topic.

## Concept metadata

Use the standard fields where they fit:

```yaml
---
type: Concept
title: "Testing patterns for LLM tools"
description: "A synthesized three-layer testing model."
tags: [testing, evals]
generated: { by: llm-wiki/<runtime>, at: 2026-09-07T12:00:00Z }
verified: { by: human:<id>, at: 2026-09-07T12:00:00Z }
status: stable
sources:
  - resource: /raw/articles/2026-09-07-testing.md
    title: "Testing source"
    id: testing-source
llm_wiki:
  category: concept
  volatility: warm
---
```

- `type` is mandatory. Use the vocabulary below.
- `generated` records the agent or process that made the latest meaningful
  change. Its `at` value is an ISO-8601 datetime with a UTC offset.
- `verified` is a mapping or a list of `{ by, at }` mappings. Do not store a
  bare date in `verified`.
- `sources` is a list of mappings. Every entry has `resource`, which is an
  absolute URL, a bundle-relative path beginning with `/`, or a relative path.
  A string list of source paths is legacy-only and must be migrated.
- `status` is `draft`, `stable`, or `deprecated`; `stale_after` is optional.
- Keep workflow-only data under `llm_wiki`, such as `category`, `kind`,
  `priority`, `next_action`, `dataset_id`, `volatility`, and legacy dates.

## Type vocabulary

| Directory/object | Type |
|---|---|
| `raw/articles` | `Source Article` |
| `raw/papers` | `Source Paper` |
| `raw/repos` | `Source Repository` |
| `raw/notes` | `Source Note` |
| `raw/data` | `Source Data` |
| `wiki/concepts`, `topics`, `references`, `theses` | `Concept`, `Topic`, `Reference`, `Thesis` |
| inventory records and views | `Inventory Item`, `Idea`, `Ingest Candidate`, `Entity`, `Corpus`, `Inventory View` |
| dataset `MANIFEST.md` | `Dataset Manifest` |
| output artifacts | `Report`, `Collection`, `Study Guide`, `Timeline`, `Glossary`, `Comparison`, or `Slides` |
| project `WHY.md` / `BRIEF.md` | `Project Rationale` / `Project Brief` |
| `config.md` / `schema.md` | `Bundle Configuration` / `Topic Guide` |

## Writer checklist

Before writing or updating any concept:

1. Preserve a complete existing `sources` list and add sources as mappings.
2. Set `generated` to the current writing actor and timestamp.
3. Preserve or explicitly update verification state; generation is not
   verification.
4. Rebuild affected `index.md` files with standard Markdown links.
5. Append a newest-first entry under today's `log.md` heading.
6. Run `scripts/llm-wiki-okf.py validate <topic-bundle>` before reporting a
   generated bundle as portable OKF.

## Legacy migration

Existing wikis using `_index.md`, path-string `sources`, or custom-only
frontmatter are read as legacy. Convert them without touching the source:

```bash
scripts/llm-wiki-okf.py migrate <legacy-topic> <new-okf-topic> --dry-run
scripts/llm-wiki-okf.py migrate <legacy-topic> <new-okf-topic>
```

Do not call a legacy topic an OKF v0.2 bundle until validation passes.
