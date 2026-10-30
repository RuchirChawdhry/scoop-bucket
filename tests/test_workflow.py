"""Contract tests for the review-first single-job workflow (no PyYAML needed)."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/excavator.yml"
UPDATE = ROOT / "scripts/update.ps1"


class WorkflowTests(unittest.TestCase):
    def test_only_schedule_and_manual_triggers(self):
        yaml = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("schedule:", yaml)
        self.assertIn("workflow_dispatch:", yaml)
        self.assertIn("17 3 * * *", yaml)
        self.assertNotIn("workflow_run:", yaml)
        self.assertNotIn("pull_request:", yaml)
        self.assertNotIn("\n  push:", yaml)

    def test_single_windows_job(self):
        yaml = WORKFLOW.read_text(encoding="utf-8")
        self.assertEqual(1, yaml.count("    runs-on:"))
        self.assertIn("runs-on: windows-2025", yaml)
        self.assertIn("timeout-minutes: 60", yaml)
        self.assertIn("name: Install Scoop", yaml)
        self.assertIn("contents: write", yaml)
        self.assertIn("pull-requests: write", yaml)
        self.assertNotIn("ScoopInstaller/GithubActions@", yaml)

    def test_updates_are_reviewed_in_pr(self):
        script = UPDATE.read_text(encoding="utf-8")
        self.assertIn("-Update -ThrowError", script)
        self.assertIn("python -m unittest discover -s tests -v", script)
        self.assertIn("scoop install", script)
        self.assertNotIn("scoop uninstall", script)
        self.assertIn("& scoop install $manifestFile", script)
        self.assertIn('(Resolve-Path -LiteralPath (Join-Path $bucket "$app.json")).Path', script)
        self.assertIn("-App $file.FullName -Update -ThrowError", script)
        self.assertNotIn('scoop install "./bucket/', script)
        self.assertNotIn("scoop bucket add .", script)
        self.assertIn("Test-Path -LiteralPath $exe -PathType Leaf", script)
        self.assertIn("gh pr create", script)
        self.assertIn("automation/scoop-", script)
        self.assertIn("git push origin", script)
        self.assertNotIn("git push origin main", script)

    def test_powershell_syntax_is_checked_before_install(self):
        yaml = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("Language.Parser]::ParseFile", yaml)
        self.assertLess(yaml.index("Validate PowerShell syntax"), yaml.index("Install Scoop"))

    def test_no_ambiguous_powershell_colon_expansions(self):
        import re
        script = UPDATE.read_text(encoding="utf-8")
        problematic = re.findall(r"\$[A-Za-z_]\w*:(?![A-Za-z_0-9])", script)
        self.assertEqual([], problematic, "PowerShell interprets $name: as a scope qualifier")

    def test_no_separate_validator_workflow(self):
        self.assertFalse((ROOT / ".github/workflows/validate.yml").exists())


if __name__ == "__main__":
    unittest.main()
