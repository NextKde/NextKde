"""Documentation checks remain usable after default installation downloads SDKs."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('check_docs', Path(__file__).parents[1] / 'check-docs.py')
docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(docs)


class DocumentationTests(unittest.TestCase):
    def check(self, root):
        with patch.object(docs, 'ROOT', root), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return docs.main()

    def test_downloaded_sdk_docs_do_not_break_source_check(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'README.md').write_text('Project documentation\n')
            sdk = root / '.build/kosctl/deps/onnxruntime'
            sdk.mkdir(parents=True)
            (sdk / 'Privacy.md').write_text('[upstream source](../not-shipped.cpp)\n')
            self.assertEqual(self.check(root), 0)

    def test_broken_project_links_still_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'README.md').write_text('[missing release guide](docs/Releasing.md)\n')
            self.assertEqual(self.check(root), 1)

    def test_existing_project_links_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'docs').mkdir()
            (root / 'README.md').write_text('[release guide](docs/Releasing.md)\n')
            (root / 'docs/Releasing.md').write_text('Release policy\n')
            self.assertEqual(self.check(root), 0)


if __name__ == '__main__':
    unittest.main()
