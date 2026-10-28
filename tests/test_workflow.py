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
        self.assertIn("0 3 * * 1,5", yaml)
        self.assertNotIn("workflow_run:", yaml)
        self.assertNotIn("pull_request:", yaml)
        self.assertNotIn("\n  push:", yaml)

    def test_single_ubuntu_slim_job(self):
        yaml = WORKFLOW.read_text(encoding="utf-8")
        self.assertEqual(1, yaml.count("    runs-on:"))
        self.assertIn("runs-on: ubuntu-slim", yaml)
        self.assertIn("timeout-minutes: 14", yaml)
        self.assertIn("repository: ScoopInstaller/Scoop", yaml)
        self.assertIn("persist-credentials: false", yaml)
        self.assertIn("contents: write", yaml)
        self.assertIn("pull-requests: write", yaml)
        self.assertNotIn("ScoopInstaller/GithubActions@", yaml)

    def test_updates_are_reviewed_in_pr(self):
        script = UPDATE.read_text(encoding="utf-8")
        self.assertIn("-Update -ThrowError", script)
        self.assertIn("python -m unittest discover -s tests -v", script)
        self.assertIn("SCOOP_CACHE", script)
        self.assertIn("7z l", script)
        self.assertNotIn("scoop install", script)
        self.assertNotIn("scoop uninstall", script)
        self.assertIn("gh pr create", script)
        self.assertIn("automation/scoop-", script)
        self.assertIn("git push origin", script)
        self.assertNotIn("git push origin main", script)

    def test_no_separate_validator_workflow(self):
        self.assertFalse((ROOT / ".github/workflows/validate.yml").exists())


if __name__ == "__main__":
    unittest.main()
