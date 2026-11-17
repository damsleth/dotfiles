#!/usr/bin/env python3
"""Focused regression checks. Temporary files stay inside the checkout."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
FUNC = (ROOT / "zsh/.config/zsh/func.zsh").read_text()


def function(name):
    marker = name + ("(){" if name == "pipe" else "() {")
    return FUNC[FUNC.index(marker):].split("\n}\n", 1)[0] + "\n}\n"


class SecurityTests(unittest.TestCase):
    def test_pipe_loopback(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
            log = Path(tmp) / "args"
            code = function("pipe") + '\nncat() { printf "%s\\n" "$@" > "$LOG"; }; lt() { sleep 0.1; }; pipe index.html example 8000; wait'
            subprocess.run(["zsh", "-fc", code], env={**os.environ, "LOG": str(log)}, check=True)
            self.assertEqual(log.read_text().splitlines()[:3], ["-lkp", "8000", "127.0.0.1"])

    def test_jwt_stdin(self):
        encode = lambda x: base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip("=")
        token = encode({"alg": "none"}) + "." + encode({"sub": "Alice"}) + "."
        # Inspect the decoder argv at invocation, then run the actual decoder.
        code = function("jwt-decode") + '\npython3() { [[ "$*" != *"$TOKEN"* ]] || return 99; command python3 "$@"; }; jwt-decode "$TOKEN"'
        result = subprocess.run(["zsh", "-fc", code], env={**os.environ, "TOKEN": token}, text=True, capture_output=True, check=True)
        self.assertIn('"sub": "Alice"', result.stdout)
        self.assertIn("=== Header ===", result.stdout)

    def test_preview_private_storage(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
            root = Path(tmp)
            cache = root / "cache"
            env = {**os.environ, "XDG_CACHE_HOME": str(cache)}
            source = root / "example.json"
            source.write_text('{"name":"Alice"}\n')
            args = ["sh", str(ROOT / "lf/.config/lf/preview"), str(source), "80", "20", "0", "0"]
            subprocess.run(args, env=env, capture_output=True)
            directory = cache / "lf"
            self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
            # Exercise the actual lfrc scroll writer with a stub remote client.
            lfrc = (ROOT / "lf/.config/lf/lfrc").read_text()
            scroll = lfrc.split("cmd preview-scroll &{{\n", 1)[1].split("\n}}", 1)[0]
            script = 'lf() { :; }; ' + scroll
            scroll_env = {**env, "f": str(source), "lf_height": "24", "id": "1"}
            subprocess.run(["sh", "-c", script, "scroll", "1"], env=scroll_env, check=True, capture_output=True)
            result = subprocess.run(args, env=env, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertTrue((directory / "preview-scroll.out").exists())
            victim = root / "victim"
            victim.write_text("untouched")
            for name in ("preview-scroll", "preview-scroll.out", "preview-scroll.out.key"):
                path = directory / name
                path.unlink(missing_ok=True)
                path.symlink_to(victim)
                self.assertEqual(subprocess.run(args, env=env, capture_output=True).returncode, 1)
                self.assertNotEqual(subprocess.run(["sh", "-c", script, "scroll", "1"], env=scroll_env, capture_output=True).returncode, 0)
                self.assertEqual(victim.read_text(), "untouched")
                path.unlink()
            shutil.rmtree(directory)
            directory.symlink_to(root, target_is_directory=True)
            self.assertEqual(subprocess.run(args, env=env, capture_output=True).returncode, 1)
            self.assertFalse((root / "preview-scroll").exists())

    @unittest.skipUnless(shutil.which("kitty"), "kitty is not installed")
    def test_kitty_authorization(self):
        code = """
from kitty.config import load_config
from kitty.main import expand_listen_on
from kitty.remote_control import remote_control_allowed
import os
o = load_config('kitty/.config/kitty/kitty.conf')
assert o.allow_remote_control == 'password'
assert o.remote_control_password == {'': ('ls', 'set-colors', 'load-config')}
assert expand_listen_on(o.listen_on, True, {}).startswith('unix:' + os.path.expanduser('~/.config/kitty/control-'))
for cmd in ('ls', 'set-colors', 'load-config'):
    assert remote_control_allowed({'cmd': cmd, 'password': ''}, o.remote_control_password, None, {})
for cmd in ('launch', 'send-text', 'get-text'):
    try:
        allowed = remote_control_allowed({'cmd': cmd, 'password': ''}, o.remote_control_password, None, {})
    except PermissionError:
        allowed = False
    assert not allowed, cmd
"""
        subprocess.run(["kitty", "+runpy", code], cwd=ROOT, check=True)


if __name__ == "__main__":
    unittest.main()
