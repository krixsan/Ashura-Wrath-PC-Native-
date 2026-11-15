"""Configure + build Asura's Wrath under the MSVC environment clang-cl needs."""
import os
import shutil
import subprocess
import sys

PORT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PS3RECOMP_DIR = os.path.join(PORT_ROOT, "02_REPOS", "ps3recomp")
PROJECT_DIR = os.path.join(PORT_ROOT, "03_ASURASWRATH_PORT")
BUILD_DIR = os.path.join(PORT_ROOT, "04_BUILD")

sys.path.insert(0, os.path.join(PS3RECOMP_DIR, "tools"))
from msvc_env import environ
env = environ()

extra_paths = [
    r"C:\Program Files\LLVM\bin",
    r"C:\Program Files\CMake\bin",
    r"C:\Users\KRIXSAN\AppData\Local\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe",
    os.path.join(PORT_ROOT, "06_TOOLS")
]
cur_path = env.get("PATH", "")
for p in extra_paths:
    if os.path.exists(p) and p.lower() not in cur_path.lower():
        cur_path = p + os.pathsep + cur_path
env["PATH"] = cur_path

cmake_exe = shutil.which("cmake", path=env["PATH"]) or r"C:\Program Files\CMake\bin\cmake.exe"
ninja_exe = shutil.which("ninja", path=env["PATH"]) or r"C:\Users\KRIXSAN\AppData\Local\Microsoft\WinGet\Packages\Ninja-build.Ninja_Microsoft.Winget.Source_8wekyb3d8bbwe\ninja.exe"

ninja_file = os.path.join(BUILD_DIR, "build.ninja")
if not os.path.exists(ninja_file):
    os.makedirs(BUILD_DIR, exist_ok=True)
    cmd = [
        cmake_exe,
        "-S", PROJECT_DIR,
        "-B", BUILD_DIR,
        "-G", "Ninja",
        f"-DCMAKE_MAKE_PROGRAM={ninja_exe}",
        f"-DPS3RECOMP_DIR={PS3RECOMP_DIR}",
        "-DCMAKE_C_COMPILER=clang-cl",
        "-DCMAKE_CXX_COMPILER=clang-cl",
        "-DCMAKE_BUILD_TYPE=Release"
    ]
    print("Running CMake configuration:", " ".join(cmd))
    subprocess.run(cmd, env=env, check=True)

print("Building target...")
args = sys.argv[1:]
# Default to -j 2 on laptop to prevent OOM on 290k-line C++ files
if not any(a.startswith("-j") or a == "-j" for a in args):
    args = ["--", "-j", "2"] + args
cmd_build = [cmake_exe, "--build", BUILD_DIR] + args
sys.exit(subprocess.run(cmd_build, env=env).returncode)
