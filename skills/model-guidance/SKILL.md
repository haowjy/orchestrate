---
name: model-guidance
description: Model tendencies and selection guidance for orchestration decisions.
---

# Model Guidance

Reference for choosing the right model and skill combination. The orchestrator reads this when deciding what to launch.

## Source of Truth

Model guidance should be loaded through the run-agent resource loader:

```bash
../run-agent/scripts/load-model-guidance.sh
```

Precedence (enforced by script):
- if any files exist under `../run-agent/references/model-guidance/*.md`, use those
- otherwise use `../run-agent/references/default-model-guidance.md`

This SKILL.md is a compatibility guide; prefer loader output for active guidance.

## Model Tendencies

| Model | Strong At | Weak At |
|---|---|---|
| `gpt-5.3-codex` | Deep multi-file implementation, exhaustive reviews, disciplined code changes | Slower and costlier on trivial tasks |
| `claude-sonnet-4-6` | Fast iteration, UI/product polish loops, quick investigations | Less exhaustive on large cross-cutting refactors |
| `claude-opus-4-6` | Architecture/design tradeoffs, nuanced reasoning, difficult correctness issues | Highest latency/cost among defaults |
| `claude-haiku-4-5` | Fast commit/message tasks and lightweight transformations | Not suitable for deep implementation/review |

## Task-Type Heuristics

- **design**: prefer `claude-opus-4-6`, then `gpt-5.3-codex`.
- **investigate**: prefer `gpt-5.3-codex` when root-cause depth matters; use `claude-sonnet-4-6` for faster loop.
- **research**: use model diversity when tradeoffs are unclear. Run 2-3 models in parallel for different perspectives.
- **plan-slice**: prefer `gpt-5.3-codex` for precise acceptance criteria.
- **implement**: default `gpt-5.3-codex`; use `claude-sonnet-4-6` for iterative UI work. Escalate to `claude-opus-4-6` for subtle correctness issues.
- **review**: for medium/high risk, run multiple model families.
- **test**: prioritize reliability and reproducibility over speed.
- **commit**: use `claude-haiku-4-5`.

## Skill-Composition Patterns

Skills are composable building blocks. Combine them to create variant behaviors without needing separate agent definitions:

| Behavior | Model | Skills | Prompt Emphasis |
|---|---|---|---|
| **Exhaustive review** | `gpt-5.3-codex` | `review` | Default — thorough senior dev review |
| **Adversarial review** | `claude-sonnet-4-6` | `review`, `smoke-test` | "Write scratch tests to break the code. Focus on edge cases, race conditions, and security." |
| **Quick sanity check** | `gpt-5.3-codex` | `review` | Use `-D brief` for fast mechanical pass |
| **Deep implementation** | `gpt-5.3-codex` | `smoke-test`, `scratchpad` | Default implementation with verification |
| **UI iteration** | `claude-sonnet-4-6` | `smoke-test` | "Iterate rapidly. Check visual result after each change." |
| **Deliberate implementation** | `claude-opus-4-6` | `smoke-test`, `scratchpad` | "Reason carefully about correctness. Document trade-offs." |
| **Multi-perspective research** | mixed | `research` | Run 2-3 models in parallel, synthesize findings |
| **Diagram-aware implementation** | any | `smoke-test`, `mermaid` | Include `mermaid` when slice involves Mermaid diagrams |

### Examples

```bash
RUNNER=../run-agent/scripts/run-agent.sh

# Adversarial review — sonnet with review + smoke-test skills
"$RUNNER" --model claude-sonnet-4-6 --skills review,smoke-test \
    --slice slice-1 \
    -p "Adversarial review: write scratch tests to break the code. Focus on concurrency, auth boundaries, and input validation."

# Quick sanity check — codex with brief report
"$RUNNER" --model gpt-5.3-codex --skills review \
    --slice slice-1 -D brief

# Deep implementation — opus for subtle correctness
"$RUNNER" --model claude-opus-4-6 --skills smoke-test,scratchpad \
    --slice slice-1

# Research with model diversity
"$RUNNER" --model gpt-5.3-codex --skills research -p "Research approach for X" &
"$RUNNER" --model claude-sonnet-4-6 --skills research -p "Research approach for X" &
wait
```

## Review Fan-Out Guidance

- **low risk**: 1 reviewer
- **medium risk**: 2 reviewers from distinct model families
- **high risk**: 3 reviewers from distinct model families
- if reviewers disagree materially: run tiebreak review with a third model family

## Practical Rules

1. Prefer the smallest model set that still controls risk.
2. Avoid running multiple models when change scope is trivial.
3. Escalate model depth only when complexity/risk justifies it.
4. Record rationale for non-default model choices in the run report.
5. When composing skills, pick the minimum set that covers the task — don't load irrelevant skills.
