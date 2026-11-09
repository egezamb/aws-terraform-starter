"""Execute bootstrap with fake service/package commands; never touch the host."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

TEMPLATE = Path(__file__).resolve().parents[1] / "templates/web-bootstrap.sh.tftpl"

class BootstrapTests(unittest.TestCase):
    def exercise(self, fail_install=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log = root / "commands"
            for name in ("dnf", "systemctl"):
                command = root / name
                command.write_text("#!/bin/bash\necho \"" + name + " $*\" >> \"$COMMAND_LOG\"\n" +
                                   ('if [ "$1" = install ]; then exit 17; fi\n' if name == "dnf" and fail_install else 'exit 0\n'))
                command.chmod(0o755)
            script = TEMPLATE.read_text().replace("${project_name}", "test-lab").replace("/var/www/html", str(root / "html"))
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"], COMMAND_LOG=str(log))
            result = subprocess.run(["bash", "-c", script], env=env, capture_output=True, text=True)
            return result, log.read_text(), (root / "html/index.html").read_text() if (root / "html/index.html").exists() else None

    def test_install_failure_does_not_start_apache(self):
        result, commands, page = self.exercise(fail_install=True)
        self.assertEqual(result.returncode, 17)
        self.assertNotIn("systemctl", commands)
        self.assertIsNone(page)

    def test_success_writes_page_and_starts_apache(self):
        result, commands, page = self.exercise()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Hello from test-lab", page)
        self.assertIn("systemctl enable --now httpd", commands)
