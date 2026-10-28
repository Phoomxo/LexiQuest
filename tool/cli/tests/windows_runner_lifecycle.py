"""Bounded Windows runner regression; no Flutter build, plugins or network."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid


def main():
    root = Path(__file__).resolve().parents[3]
    fixture = Path(__file__).parent / "fixtures/windows-runner"
    output = root / "build/f01-native" / uuid.uuid4().hex
    output.mkdir(parents=True)
    vswhere = Path(os.environ["ProgramFiles(x86)"]) / "Microsoft Visual Studio/Installer/vswhere.exe"
    install = subprocess.check_output([
        str(vswhere), "-latest", "-products", "*", "-requires",
        "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath",
    ], text=True).strip()
    if not install:
        raise RuntimeError("Required installed MSVC/Windows SDK is unavailable")
    setup = Path(install) / "Common7/Tools/VsDevCmd.bat"
    # Read the compiler environment without printing its contents.
    raw = subprocess.check_output(
        f'cmd.exe /d /s /c ""{setup}" -no_logo -arch=x64 >nul && set"', text=True)
    env = dict(os.environ)
    for line in raw.splitlines():
        key, sep, value = line.partition("=")
        if sep and key:
            env[key] = value
    compiler = shutil.which("cl.exe", path=env.get("Path", env.get("PATH")))
    if not compiler:
        raise RuntimeError("MSVC environment did not resolve cl.exe")
    exe = output / "runner_test.exe"
    sources = [fixture / "runner_test.cpp", fixture / "query_failure.cpp",
               root / "windows/runner/utils.cpp", root / "windows/runner/flutter_window.cpp",
               root / "windows/runner/win32_window.cpp"]
    command = [compiler, "/nologo", "/std:c++17", "/EHsc", "/MD", "/Od", "/DUNICODE",
               "/D_UNICODE", "/DNOMINMAX", f"/I{fixture}", f"/I{root / 'windows'}",
               *map(str, sources), f"/Fe{exe}", f"/Fo{output}{os.sep}", "/link",
               "user32.lib", "shell32.lib", "dwmapi.lib", "advapi32.lib", "gdi32.lib"]
    compiled = subprocess.run(command, env=env, capture_output=True, timeout=120)
    (output / "compile.stdout").write_bytes(compiled.stdout)
    (output / "compile.stderr").write_bytes(compiled.stderr)
    if compiled.returncode:
        print(compiled.stdout.decode(errors="replace"))
        print(compiled.stderr.decode(errors="replace"))
        return compiled.returncode
    results = []
    for name in ["utf16-positive", "utf16-invalid", "utf16-query", "utf16-cli",
                 "font-before", "font-after", "font-normal"]:
        args = [str(exe), name]
        if name == "utf16-cli":
            args.append("\ud800")
        run = subprocess.run(args, capture_output=True, timeout=30,
                             creationflags=subprocess.CREATE_NO_WINDOW)
        (output / f"{name}.stdout").write_bytes(run.stdout)
        (output / f"{name}.stderr").write_bytes(run.stderr)
        results.append({"case": name, "exitCode": run.returncode})
        print(f"{name}: exit={run.returncode} {run.stdout.decode(errors='replace').strip()}")
    receipt = {"compiler": compiler, "compilerSha256": hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
               "windowsSdkVersion": env.get("WindowsSDKVersion"),
               "vcToolsVersion": env.get("VCToolsVersion"), "command": command, "results": results,
               "meaning": "Actual Win32 runner dispatch/input with a fake Flutter engine; no installed app/device claim"}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(f"Native evidence: {output}")
    return int(any(row["exitCode"] for row in results))


if __name__ == "__main__":
    sys.exit(main())
