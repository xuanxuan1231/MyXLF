#!/usr/bin/env python3
"""生成 MyXLF 更新清单（manifest.json）。

R2 只托管 Android APK 和清单；iOS / 桌面客户端的下载地址指向 GitHub
Release 资产。所有平台都读取同一份清单，不访问 GitHub API。

用法示例：
    python3 scripts/publish_update_manifest.py \
        --dist dist \
        --version 1.2.3 \
        --build 123 \
        --revision 123456789-1 \
        --notes release-notes.md \
        --base-url https://myxlf.helloswx.top \
        --github-download-base https://github.com/owner/repo/releases/download/v1.2.3 \
        --release-url https://github.com/owner/repo/releases/tag/v1.2.3 \
        --output dist/manifest.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

# 平台 -> 候选产物。按顺序取第一个存在的文件。
# Android 单独处理（见 `build_android_entry`），因为需要同时支持按 ABI 拆分的安装包。
ARTIFACTS: dict[str, list[str]] = {
    "ios": [
        "MyXLF-{version}.ipa",
        "MyXLF-{version}-unsigned.ipa",
    ],
    "windows": ["MyXLF-{version}-windows-x64.zip"],
    "macos": ["MyXLF-{version}-macos.zip"],
    "linux": ["MyXLF-{version}-linux-x64.tar.gz"],
}

# 与 `flutter build apk --split-per-abi` 的产物后缀、客户端 `Abi.current()` 映射一致。
ANDROID_ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")

# 没有通用包时，顶层 `url` 退回哪个 ABI。
# 选 arm64 是因为 32 位专用设备已经非常少见，而 64 位专用设备越来越多。
ANDROID_FALLBACK_ABI = "arm64-v8a"


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_android_entry(
    *,
    dist: Path,
    version: str,
    build: int,
    base: str,
    version_dir: str,
) -> dict | None:
    """生成 Android 平台条目。

    同时写入按 ABI 拆分的 `abis` 与顶层通用条目：

    - 新客户端读取 `abis.<abi>`，只下载匹配当前进程的安装包；
    - 旧客户端只认识顶层 `url`，因此在过渡期仍提供通用 APK 作为回退。
    """
    universal = dist / f"MyXLF-{version}.apk"
    abi_paths = {
        abi: dist / f"MyXLF-{version}-{abi}.apk" for abi in ANDROID_ABIS
    }
    abi_paths = {abi: path for abi, path in abi_paths.items() if path.is_file()}

    if not universal.is_file() and not abi_paths:
        return None

    def artifact(path: Path) -> dict:
        return {
            "url": f"{base}/{version_dir}/{urllib.parse.quote(path.name)}",
            "size": path.stat().st_size,
            "sha256": sha256_of(path),
        }

    # 顶层条目必须能被不认识 `abis` 的旧客户端直接安装：优先通用包，
    # 没有时退回 arm64（覆盖绝大多数设备）。
    if universal.is_file():
        legacy = universal
    elif ANDROID_FALLBACK_ABI in abi_paths:
        legacy = abi_paths[ANDROID_FALLBACK_ABI]
    else:
        legacy = next(iter(abi_paths.values()))

    if not universal.is_file() and abi_paths:
        print(
            "警告：未找到通用 APK，顶层 android.url 将指向 "
            f"{legacy.name}，32 位专用设备可能无法安装。",
            file=sys.stderr,
        )

    entry: dict = {"version": version, "build": build}
    entry.update(artifact(legacy))
    if abi_paths:
        entry["abis"] = {
            abi: {"version": version, "build": build, **artifact(path)}
            for abi, path in abi_paths.items()
        }
    return entry


def build_manifest(
    *,
    dist: Path,
    version: str,
    build: int,
    base_url: str,
    release_url: str,
    notes: str,
    revision: str = "",
    github_download_base: str = "",
) -> dict:
    base = base_url.rstrip("/")
    github_base = github_download_base.rstrip("/")
    # 把构建标识写进路径：同一版本重跑时也不会命中上一轮的 immutable 缓存。
    version_dir = f"releases/v{version}"
    if revision:
        version_dir += f"/{revision}"
    platforms: dict[str, dict] = {}

    android = build_android_entry(
        dist=dist,
        version=version,
        build=build,
        base=base,
        version_dir=version_dir,
    )
    if android is not None:
        platforms["android"] = android

    for platform, candidates in ARTIFACTS.items():
        for template in candidates:
            name = template.format(version=version)
            path = dist / name
            if not path.is_file():
                continue
            if not github_base:
                continue
            # 其他平台不占 R2 空间，直接指向 GitHub Release 资产。
            platforms[platform] = {
                "version": version,
                "build": build,
                "url": f"{github_base}/{urllib.parse.quote(name)}",
                "size": path.stat().st_size,
                "sha256": sha256_of(path),
            }
            break

    prerelease = "-" in version
    return {
        "schema": 1,
        "app": "MyXLF",
        "channel": "prerelease" if prerelease else "stable",
        "prerelease": prerelease,
        "version": version,
        "build": build,
        "released_at": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "release_url": release_url,
        "release_notes": notes,
        "platforms": platforms,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dist", type=Path, default=Path("dist"))
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--release-url", default="")
    parser.add_argument("--github-download-base", default="")
    parser.add_argument("--revision", default="")
    parser.add_argument("--notes", type=Path)
    parser.add_argument("--output", type=Path, default=Path("dist/manifest.json"))
    args = parser.parse_args()

    version = (
        args.version.strip().removeprefix("v").removeprefix("V").split("+", 1)[0]
    )
    if not version:
        parser.error("--version 不能为空")
    if "/" in version or "\\" in version:
        parser.error("--version 不能包含路径分隔符")
    if "/" in args.revision or "\\" in args.revision:
        parser.error("--revision 不能包含路径分隔符")
    if not args.base_url.strip():
        parser.error("--base-url 不能为空")

    notes = ""
    if args.notes and args.notes.is_file():
        notes = args.notes.read_text(encoding="utf-8").strip()

    manifest = build_manifest(
        dist=args.dist,
        version=version,
        build=args.build,
        base_url=args.base_url.strip(),
        release_url=args.release_url.strip(),
        notes=notes,
        revision=args.revision.strip(),
        github_download_base=args.github_download_base.strip(),
    )

    if not manifest["platforms"]:
        print("错误：dist 中没有找到任何可发布的平台产物", file=sys.stderr)
        return 1
    if "android" not in manifest["platforms"]:
        print(
            "警告：未找到 Android APK，本次清单不包含 Android 更新",
            file=sys.stderr,
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"已生成更新清单：{args.output}")
    for platform, entry in manifest["platforms"].items():
        print(f"  {platform}: {entry['url']} ({entry['size']} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
