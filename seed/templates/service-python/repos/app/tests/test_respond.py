"""The suite the Containerfile runs. It is the image's only gate: if it
goes red the build stops and no image is produced."""
import unittest

from src.server import respond


class TestRespond(unittest.TestCase):
    def test_healthz(self):
        # The readinessProbe polls this path: if it stops answering, the
        # pod never becomes ready and the deploy hangs with no error.
        self.assertEqual(respond("/healthz"), b"ok\n")

    def test_root(self):
        self.assertIn(b"__ORG__", respond("/"))


if __name__ == "__main__":
    unittest.main()
