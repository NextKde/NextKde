"""Catalogue preparation is read-only towards KMusic; run tests in a VM."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'kmusic_catalog', Path(__file__).resolve().parents[1] / 'prepare-kmusic-catalog.py')
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class CatalogueTest(unittest.TestCase):
    def test_reject_mutable_revision_without_network(self):
        def unexpected(url):
            self.fail('A mutable revision must not cause a network request')
        for revision in ['main', 'latest', 'abcdef', '../main', 'A' * 40]:
            with self.assertRaises(ValueError):
                catalog.release(revision, unexpected)

    def test_pin_both_files_at_one_revision(self):
        calls = []
        def fetch(url):
            calls.append(url)
            return url.encode()
        release = catalog.release('a' * 40, fetch)
        self.assertEqual(set(release['sha256']), set(catalog.FILES))
        self.assertEqual(len(calls), 2)
        self.assertTrue(all('/' + 'a' * 40 + '/' in url for url in calls))
        self.assertTrue(all(len(value) == 64 for value in release['sha256'].values()))

    def test_missing_or_oversized_file(self):
        for data in [b'', b'x' * (catalog.MAX_BYTES + 1)]:
            with self.assertRaises(ValueError):
                catalog.release('a' * 40, lambda url: data)
