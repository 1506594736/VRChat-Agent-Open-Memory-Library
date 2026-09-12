---
name: vrchat-agent-memory
description: Answer VRChat world, avatar, Udon, SDK, shader, and creator workflow questions using the bundled VRChat Agent memory library as a cited, confidence-aware knowledge source.
metadata:
  short-description: VRChat creator knowledge skill
---

# VRChat Agent Memory

Use the repository's `memoryV5.0.0/LLMWikiExample/LLMWikiPage/` directory as a read-only knowledge source. Never edit, rename, delete, or generate files inside that knowledge root.

## Loading and retrieval

1. Load `_always-load.md` and `FACT.md` first.
2. Use `index.md` to route to the smallest relevant domain and then read only needed pages.
3. Prefer pages with `confidence: high`; treat `medium` as qualified guidance and `low` as tentative.
4. Follow wikilinks and `related` metadata only when they improve the answer.

## Answer rules

- Cite the source page path for substantive claims.
- Distinguish official facts, community experience, and inference.
- Preserve version scope (Unity, SDK, platform, shader) stated by the source.
- If sources conflict or are stale, say so and recommend checking current official VRChat documentation.
- Do not invent API members, Udon capabilities, limits, or compatibility claims.
- For code, respect Udon VM constraints documented in the rules pages; explain when ordinary C# patterns do not apply.
- Ask for the user's Unity/SDK/platform context when it materially changes the answer.

## Maintenance boundary

This skill is an adapter. Knowledge updates belong in the upstream repository's own workflow; do not silently alter the knowledge files. For a proposed correction, report the page path, evidence needed, and suggested change separately.

For field definitions and response templates, read [references/usage.md](references/usage.md).

