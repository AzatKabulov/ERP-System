"""Deployment script regressions using fake Docker; never touches a real Docker host."""

import gzip
import os
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class DeploySafetyTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="erp-deploy-check-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.scripts = self.root / "scripts/deploy"
        shutil.copytree(ROOT / "scripts/deploy", self.scripts)
        infra = self.root / "infra"
        infra.mkdir()
        (infra / ".env").write_text("POSTGRES_USER=erp\nPOSTGRES_DB=erp\n")
        self.log = self.root / "docker.log"
        binary = self.root / "bin"
        binary.mkdir()
        docker = binary / "docker"
        docker.write_text(
            "#!/bin/bash\n"
            'printf "%s\\n" "$*" >> "$DOCKER_LOG"\n'
            'case "$1" in\n'
            "info) exit 0 ;;\n"
            'inspect) [ "$MISSING_MOUNT" = true ] || echo this_shop_privatefiles ;;\n'
            'compose) case "$2" in\n'
            'ps) if [[ "$*" != *"--status running"* || "$STOPPED_API" != true ]]; '
            "then echo this_shop_api; fi ;;\n"
            'exec) if [ "$5" = pg_dump ]; then [ "$FAIL_DUMP" != true ] || exit 1; '
            'echo "-- synthetic dump"; fi ;;\n'
            "esac ;;\n"
            'run) [ "$FAIL_ARCHIVE" != true ] || exit 1\n'
            'destination=""\n'
            'while [ "$#" -gt 0 ]; do\n'
            '  if [ "$1" = -v ] && [[ "$2" = *:/backup ]]; then destination="${2%:/backup}"; fi\n'
            '  if [ "$1" = czf ]; then tar czf "$destination/${2##*/}" -T /dev/null; break; fi\n'
            "  shift\n"
            "done ;;\n"
            "volume) echo other_shop_privatefiles; echo this_shop_privatefiles ;;\n"
            "esac\n"
            "exit 0\n"
        )
        docker.chmod(0o700)
        self.env = {
            **os.environ,
            "PATH": f"{binary}:/usr/bin:/bin",
            "DOCKER_LOG": str(self.log),
            "MISSING_MOUNT": "false",
            "STOPPED_API": "false",
            "FAIL_DUMP": "false",
            "FAIL_ARCHIVE": "false",
        }

    def run_script(self, name, *args, answer=""):
        return subprocess.run(
            ["/bin/bash", str(self.scripts / name), *map(str, args)],
            input=answer,
            text=True,
            capture_output=True,
            env=self.env,
            timeout=10,
        )

    def backup_files(self):
        dump = self.root / "db.sql.gz"
        dump.write_bytes(gzip.compress(b"-- synthetic database"))
        files = self.root / "files.tar.gz"
        with tarfile.open(files, "w:gz"):
            pass
        return dump, files

    def test_backup_uses_only_the_current_api_mount(self):
        result = self.run_script("backup.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        self.assertIn("inspect --format", log)
        self.assertIn("this_shop_api", log)
        self.assertIn("this_shop_privatefiles:/data:ro", log)
        self.assertNotIn("volume ls", log)
        self.assertNotIn("other_shop_privatefiles:/data", log)
        backup = next((self.root / "infra/backups").glob("db-*.sql.gz"))
        self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        self.assertEqual(backup.parent.stat().st_mode & 0o777, 0o700)
        self.assertLess(log.index("stop api"), log.index("pg_dump"))
        self.assertLess(log.index("pg_dump"), log.index("start api"))

    def test_backup_refuses_a_missing_files_mount(self):
        self.env["MISSING_MOUNT"] = "true"
        result = self.run_script("backup.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("pg_dump", self.log.read_text())

    def test_failed_database_dump_restarts_api_and_publishes_no_backup(self):
        self.env["FAIL_DUMP"] = "true"
        result = self.run_script("backup.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("start api", self.log.read_text())
        self.assertEqual(list((self.root / "infra/backups").iterdir()), [])

    def test_failed_files_archive_restarts_api_and_publishes_no_backup(self):
        self.env["FAIL_ARCHIVE"] = "true"
        result = self.run_script("backup.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("start api", self.log.read_text())
        self.assertEqual(list((self.root / "infra/backups").iterdir()), [])

    def test_backup_does_not_start_an_api_that_was_stopped(self):
        self.env["STOPPED_API"] = "true"
        result = self.run_script("backup.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        self.assertNotIn("stop api", log)
        self.assertNotIn("start api", log)

    def test_a_second_backup_cannot_restart_api_during_the_first_snapshot(self):
        lock = self.root / "infra/backups/.backup-in-progress"
        lock.mkdir(parents=True)
        result = self.run_script("backup.sh")
        self.assertNotEqual(result.returncode, 0)
        log = self.log.read_text()
        self.assertNotIn("stop api", log)
        self.assertNotIn("pg_dump", log)

    def test_restore_checks_mount_before_stopping_api_or_dropping_database(self):
        self.env["MISSING_MOUNT"] = "true"
        result = self.run_script("restore.sh", *self.backup_files(), answer="restore\n")
        self.assertNotEqual(result.returncode, 0)
        log = self.log.read_text()
        self.assertNotIn("stop api", log)
        self.assertNotIn("DROP DATABASE", log)

    def test_restore_uses_only_current_project_mount(self):
        result = self.run_script("restore.sh", *self.backup_files(), answer="restore\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.log.read_text()
        self.assertIn("this_shop_privatefiles:/data", log)
        self.assertNotIn("volume ls", log)

    def test_corrupt_database_is_refused_before_restore(self):
        dump, files = self.backup_files()
        dump.write_bytes(b"truncated gzip")
        result = self.run_script("restore.sh", dump, files, answer="restore\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_corrupt_files_archive_is_refused_before_restore(self):
        dump, files = self.backup_files()
        files.write_bytes(b"truncated archive")
        result = self.run_script("restore.sh", dump, files, answer="restore\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_health_check_keeps_tls_verification_enabled(self):
        curl = self.root / "bin/curl"
        curl.write_text(
            '#!/bin/bash\nfor value in "$@"; do\n'
            'case "$value" in -k|--insecure|-sk) exit 99 ;; esac\ndone\nprintf 200\n'
        )
        curl.chmod(0o700)
        result = subprocess.run(
            [
                "/bin/bash",
                "-c",
                'source "$1"; wait_healthy https://shop.example.test',
                "check",
                str(self.scripts / "common.sh"),
            ],
            capture_output=True,
            env=self.env,
            timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
