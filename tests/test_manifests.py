"""Fast, offline checks for the personal Scoop bucket."""
import json
import unittest
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1] / "bucket"
ELECTRON = {
    "todoist": "Todoist.exe",
    "toggl": "Toggl 2.0.exe",
    "wispr-flow": "payload\\lib\\net45\\Wispr Flow.exe",
}
INITIAL = {"todoist", "toggl", "wispr-flow", "freefilesync", "directorymonitor", "yq"}


def downloads(obj):
    if "architecture" in obj:
        return obj["architecture"]
    return {"default": obj}


class ManifestTests(unittest.TestCase):
    def test_expected_manifests_exist(self):
        self.assertTrue(INITIAL.issubset({p.stem for p in ROOT.glob("*.json")}))

    def test_structure_and_download_hashes(self):
        files = sorted(ROOT.glob("*.json"))
        self.assertTrue(files)
        for file in files:
            with self.subTest(manifest=file.name):
                data = json.loads(file.read_text(encoding="utf-8"))
                for key in ("version", "description", "homepage", "license", "checkver", "autoupdate"):
                    self.assertIn(key, data)
                self.assertRegex(data["version"], r"^\d+(?:\.\d+)+$")
                current = downloads(data)
                future = downloads(data["autoupdate"])
                self.assertEqual(set(current), set(future))
                for arch, spec in current.items():
                    self.assertIn("url", spec)
                    self.assertRegex(spec["hash"], r"^[a-fA-F0-9]{64}$")
                    url = spec["url"].split("#/", 1)[0]
                    self.assertIn(urlsplit(url).scheme, ("http", "https"))
                    self.assertEqual("https", urlsplit(url).scheme)
                    self.assertIn("url", future[arch])
                    self.assertIn("$version", future[arch]["url"])

    def test_electron_entrypoints_and_extractors(self):
        for app, exe in ELECTRON.items():
            with self.subTest(app=app):
                data = json.loads((ROOT / f"{app}.json").read_text(encoding="utf-8"))
                shortcuts = [row[0] for row in data["shortcuts"]]
                self.assertIn(exe, shortcuts)
                preinstall = "\n".join(data["pre_install"])
                self.assertIn("Expand-7zipArchive", preinstall)
                self.assertIn("throw", preinstall)
                self.assertIn(exe.rsplit("\\", 1)[-1].rsplit("/", 1)[-1], preinstall)

    def test_todoist_architectures(self):
        data = json.loads((ROOT / "todoist.json").read_text(encoding="utf-8"))
        self.assertEqual(set(data["architecture"]), {"64bit", "arm64"})
        for arch in ("64bit", "arm64"):
            self.assertEqual(data["autoupdate"]["architecture"][arch]["hash"], {"mode": "download"})


if __name__ == "__main__":
    unittest.main()
