import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("alt_store", ROOT / "update_alt_store.py")
alt_store = importlib.util.module_from_spec(spec)
spec.loader.exec_module(alt_store)


class AltStoreTest(unittest.TestCase):
    def test_update_removes_upstream_history_and_preserves_own_releases(self):
        own = "https://github.com/CyrilPeng/Venera-Next/releases/download/v1.8.0/app.ipa"
        upstream = "https://github.com/venera-app/venera/releases/download/v1.6.3/app.ipa"
        data = {"apps": [{"bundleIdentifier": "com.github.cyrilpeng.veneranext",
                          "versions": [{"version": "1.8.0", "downloadURL": own},
                                       {"version": "1.6.3", "downloadURL": upstream}]}],
                "news": [{"url": own}, {"url": upstream}]}
        release = {"tag_name": "v2.0.0", "published_at": "2026-09-28T00:00:00Z",
                   "assets": [{"name": "VeneraNext-ios-2.0.0.ipa", "size": 123,
                               "browser_download_url": own.replace("v1.8.0", "v2.0.0")}]}
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "source.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            alt_store.update_json_file_release(path, release)
            alt_store.update_json_file_release(path, release)
            updated = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual([x["version"] for x in updated["apps"][0]["versions"]],
                             ["2.0.0", "1.8.0"])
            self.assertEqual(len(updated["news"]), 2)

    def test_rejects_foreign_and_lookalike_urls(self):
        for url in ("https://github.com/venera-app/venera/releases/download/a.ipa",
                    "https://github.com.evil.test/CyrilPeng/venera-next/releases/a",
                    "https://github.com/CyrilPeng/venera-next-other/releases/a"):
            self.assertFalse(alt_store.is_project_release_url(url))

    def test_checked_in_source_only_distributes_project_releases(self):
        data = json.loads((ROOT / "alt_store.json").read_text(encoding="utf-8"))
        for app in data["apps"]:
            for entry in app["versions"]:
                self.assertTrue(alt_store.is_project_release_url(entry["downloadURL"]))
        for entry in data["news"]:
            self.assertTrue(alt_store.is_project_release_url(entry["url"]))
