// orchestrate.ts — OpenCode wrapper for orchestrate hooks.
//
// Thin wrapper that delegates to the shared shell scripts via execSync,
// passing JSON on stdin and reading additionalContext from stdout.
//
// Hook scripts are copied to .orchestrate/hooks/scripts/ by sync.sh pull.

import { execSync } from "child_process";
import { resolve } from "path";

const SCRIPTS_DIR = resolve(process.cwd(), ".orchestrate/hooks/scripts");

function runHook(script: string, input: Record<string, unknown>): string | undefined {
  try {
    const result = execSync(`bash "${SCRIPTS_DIR}/${script}"`, {
      input: JSON.stringify(input),
      encoding: "utf-8",
      timeout: 10_000,
    });
    if (!result.trim()) return undefined;
    const parsed = JSON.parse(result);
    return parsed.additionalContext;
  } catch {
    return undefined;
  }
}

export default {
  name: "orchestrate",

  hooks: {
    "session.created": (event: { cwd?: string; transcript_path?: string; source?: string }) => {
      const context = runHook("session-start.sh", {
        cwd: event.cwd ?? process.cwd(),
        transcript_path: event.transcript_path ?? "",
        source: event.source ?? "startup",
      });
      if (context) return { additionalContext: context };
    },

    "tool.execute.before": (event: { tool_name?: string }) => {
      if (event.tool_name !== "EnterPlanMode") return;
      const context = runHook("plan-mode.sh", { tool_name: "EnterPlanMode" });
      if (context) return { additionalContext: context };
    },
  },
};
