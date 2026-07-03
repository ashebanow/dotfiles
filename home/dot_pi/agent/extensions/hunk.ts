import { execSync } from "node:child_process";
import { dirname } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("resources_discover", async () => {
    try {
      const skillFile = execSync("hunk skill path", { encoding: "utf8" }).trim();
      // skillFile is .../skills/hunk-review/SKILL.md — walk up to skills/ for discovery
      const skillsDir = dirname(dirname(skillFile));
      return { skillPaths: [skillsDir] };
    } catch {
      // hunk not installed — silently skip
    }
  });
}
