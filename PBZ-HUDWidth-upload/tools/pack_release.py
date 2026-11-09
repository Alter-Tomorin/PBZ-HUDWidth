# -*- coding: utf-8 -*-
"""把仓库打成可直接分发的 zip。

用法（在仓库根目录）：
    python tools/pack_release.py

产物：
    dist/PBZ_HUDWidth_v1.0.zip
    dist/PBZ_HUDWidth_v1.0/        （解压后的样子，便于检查）
"""

import os
import shutil
import sys
import zipfile

VERSION = "v1.0"
NAME = "PBZ_HUDWidth"

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")
STAGE = os.path.join(DIST, f"{NAME}_{VERSION}")
EXE_SRC = os.path.join(ROOT, "configurator", "dist", f"{NAME}_Configurator.exe")
ZIP_PATH = os.path.join(DIST, f"{NAME}_{VERSION}.zip")

# 顶层要带的文件
ROOT_FILES = [
    "README.md",
    "简单的使用说明.txt",
    "install.ps1",
    "uninstall.ps1",
]
# 要带的目录（整份拷贝）
ROOT_DIRS = [
    NAME,  # Mod 本体
]


def main():
    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(STAGE)

    missing = []
    for f in ROOT_FILES:
        src = os.path.join(ROOT, f)
        if os.path.isfile(src):
            shutil.copy2(src, os.path.join(STAGE, f))
        else:
            missing.append(f)

    for d in ROOT_DIRS:
        src = os.path.join(ROOT, d)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(STAGE, d))
        else:
            missing.append(d + "/")

    if os.path.isfile(EXE_SRC):
        shutil.copy2(EXE_SRC, os.path.join(STAGE, os.path.basename(EXE_SRC)))
        has_exe = True
    else:
        has_exe = False

    if missing:
        print("警告：以下内容缺失，已跳过")
        for m in missing:
            print("  -", m)
        print()

    if os.path.exists(ZIP_PATH):
        os.remove(ZIP_PATH)

    with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(STAGE):
            for f in files:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, DIST)
                z.write(full, rel)

    size = os.path.getsize(ZIP_PATH) / 1024 / 1024
    print(f"打包完成: {ZIP_PATH}  ({size:.1f} MB)")
    print("内容:")
    with zipfile.ZipFile(ZIP_PATH) as z:
        for n in z.namelist():
            print("  ", n)

    if not has_exe:
        print()
        print("提示：未找到配置器 exe，zip 里不含它。")
        print("      先执行 configurator\\build.ps1 打包，再重跑本脚本。")
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
