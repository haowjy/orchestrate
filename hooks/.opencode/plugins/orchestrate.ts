import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { Plugin } from "@opencode-ai/plugin";

const BASE_DIRECTORY_SKILL_PATTERN = /Base directory for this skill:\s*[^\n]*[\\/]skills[\\/](?<skill>[A-Za-z0-9._-]+)/g;
const LAUNCHING_SKILL_PATTERN = /Launching skill:\s*(?<skill>[A-Za-z0-9._-]+)/g;
const UNPIN_COMMAND_PATTERN = /\/unpin\s+(?<skill>[A-Za-z0-9._-]+)/g;
const UNPIN_SIGNAL_PATTERN = /SKILL_UNPIN:(?<skill>[A-Za-z0-9._-]+)/g;

function normalizeSkillName(value: string): string {
  return value.trim().toLowerCase();
}

function getMatchSkill(match: RegExpExecArray): string | undefined {
  const candidate = match.groups?.skill ?? match[1];
  if (typeof candidate !== "string") return undefined;
  const normalized = normalizeSkillName(candidate);
  return normalized.length > 0 ? normalized : undefined;
}

function collectPatternMatches(text: string, pattern: RegExp): string[] {
  const result: string[] = [];
  pattern.lastIndex = 0;

  let match: RegExpExecArray | null = null;
  while ((match = pattern.exec(text)) !== null) {
    const skill = getMatchSkill(match);
    if (skill) result.push(skill);
  }

  return result;
}

function getTextPartText(part: unknown): string | undefined {
  if (!part || typeof part !== "object") return undefined;
  const maybeTextPart = part as { type?: unknown; text?: unknown };
  if (maybeTextPart.type !== "text") return undefined;
  if (typeof maybeTextPart.text !== "string") return undefined;
  return maybeTextPart.text;
}

function isNotFoundError(error: unknown): boolean {
  return !!error && typeof error === "object" && "code" in error && (error as { code?: string }).code === "ENOENT";
}

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

async function readStickyAllowList(directory: string): Promise<Set<string> | undefined> {
  const configPath = join(directory, ".orchestrate", "sticky-skills.conf");

  try {
    const content = await readFile(configPath, "utf-8");
    const allowList = new Set<string>();
    for (const rawLine of content.split(/\r?\n/g)) {
      const line = rawLine.trim();
      if (!line || line.startsWith("#")) continue;
      allowList.add(normalizeSkillName(line));
    }
    return allowList;
  } catch (error) {
    if (isNotFoundError(error)) {
      // Missing config means "allow all" by design.
      return undefined;
    }
    console.error(
      `[orchestrate] warning: failed to read sticky allow-list at ${configPath}: ${getErrorMessage(error)}`,
    );
    return undefined;
  }
}

async function readSkillMarkdown(directory: string, skillName: string): Promise<string | undefined> {
  const candidates = [
    join(directory, ".claude", "skills", skillName, "SKILL.md"),
    join(directory, ".cursor", "skills", skillName, "SKILL.md"),
    join(directory, ".opencode", "skills", skillName, "SKILL.md"),
  ];

  for (const candidate of candidates) {
    try {
      return await readFile(candidate, "utf-8");
    } catch (error) {
      if (isNotFoundError(error)) continue;
      console.error(
        `[orchestrate] warning: failed reading ${candidate} for "${skillName}": ${getErrorMessage(error)}`,
      );
    }
  }

  console.error(
    `[orchestrate] warning: skipping sticky skill "${skillName}" because SKILL.md was not found in known locations`,
  );
  return undefined;
}

export const OrchestratePlugin: Plugin = async (pluginInput) => {
  // Keep sticky skill state in memory for this OpenCode process/session.
  const activeSkills = new Set<string>();

  return {
    "chat.message": async (_input, output) => {
      try {
        for (const part of output.parts) {
          const text = getTextPartText(part);
          if (!text) continue;

          const activated = [
            ...collectPatternMatches(text, BASE_DIRECTORY_SKILL_PATTERN),
            ...collectPatternMatches(text, LAUNCHING_SKILL_PATTERN),
          ];
          for (const skillName of activated) {
            activeSkills.add(skillName);
          }

          const unpinned = [
            ...collectPatternMatches(text, UNPIN_COMMAND_PATTERN),
            ...collectPatternMatches(text, UNPIN_SIGNAL_PATTERN),
          ];
          for (const skillName of unpinned) {
            activeSkills.delete(skillName);
          }
        }
      } catch (error) {
        console.error(`[orchestrate] warning: failed processing chat.message hook: ${getErrorMessage(error)}`);
      }
    },

    "experimental.session.compacting": async (_input, output) => {
      try {
        const allowList = await readStickyAllowList(pluginInput.directory);
        const reinjected: string[] = [];

        const skills = [...activeSkills].sort((left, right) => left.localeCompare(right));
        for (const skillName of skills) {
          if (allowList && !allowList.has(skillName)) continue;

          const skillMarkdown = await readSkillMarkdown(pluginInput.directory, skillName);
          if (!skillMarkdown) continue;

          output.context.push(skillMarkdown);
          reinjected.push(skillName);
        }

        if (reinjected.length > 0) {
          console.error(`[orchestrate] reinjecting sticky skills during compaction: ${reinjected.join(", ")}`);
        }
      } catch (error) {
        console.error(
          `[orchestrate] warning: failed processing experimental.session.compacting hook: ${getErrorMessage(error)}`,
        );
      }
    },
  };
};

export default OrchestratePlugin;
