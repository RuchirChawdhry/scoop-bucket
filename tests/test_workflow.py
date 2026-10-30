"""Fast static safety checks. Functional PowerShell tests live in test_update.ps1."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / '.github/workflows/excavator.yml'
UPDATE = ROOT / 'scripts/update.ps1'


class WorkflowTests(unittest.TestCase):
    def test_only_daily_schedule_and_manual_dispatch(self):
        yaml = WORKFLOW.read_text(encoding='utf-8')
        self.assertIn('workflow_dispatch:', yaml)
        self.assertIn('17 3 * * *', yaml)
        for event in ('workflow_run:', 'pull_request:', '\n  push:'):
            self.assertNotIn(event, yaml)

    def test_single_windows_job_and_restricted_permissions(self):
        yaml = WORKFLOW.read_text(encoding='utf-8')
        self.assertEqual(yaml.count('    runs-on:'), 1)
        self.assertIn('runs-on: windows-2025', yaml)
        self.assertIn('contents: write', yaml)
        self.assertIn('pull-requests: write', yaml)
        self.assertIn('Test updater behavior', yaml)
        self.assertLess(yaml.index('Test updater behavior'), yaml.index('Install Scoop'))

    def test_intent_revealing_functions(self):
        script = UPDATE.read_text(encoding='utf-8')
        for name in ('Get-PendingPR', 'Update-Manifests', 'Test-Manifests',
                     'Get-ManifestExecutables', 'New-PRReport', 'Publish-PR', 'Invoke-Maintenance'):
            self.assertIn(f'function {name}', script)
        self.assertIn("$MyInvocation.InvocationName -ne '.'", script)

    def test_preserve_manifest_and_publishing_safety(self):
        script = UPDATE.read_text(encoding='utf-8')
        self.assertIn('-App $file.FullName -Update -ThrowError', script)
        self.assertIn('& scoop install $change.Path', script)
        self.assertNotIn('scoop uninstall', script)
        self.assertNotIn('scoop bucket add .', script)
        self.assertIn('gh pr create', script)
        self.assertIn('git push origin "HEAD:refs/heads/$branch"', script)
        self.assertNotIn('git push origin main', script)
        self.assertEqual([], re.findall(r'\$[A-Za-z_]\w*:(?![A-Za-z_0-9])', script))

    def test_powershell_preflight_and_behavior_tests(self):
        yaml = WORKFLOW.read_text(encoding='utf-8')
        self.assertIn('Language.Parser]::ParseFile', yaml)
        self.assertTrue((ROOT / 'tests/test_update.ps1').exists())
        self.assertFalse((ROOT / '.github/workflows/validate.yml').exists())


if __name__ == '__main__':
    unittest.main()
