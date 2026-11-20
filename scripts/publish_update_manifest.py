#!/usr/bin/env python3
"""生成 MyXLF 多平台更新清单（manifest.json）。

发布工作流在收集完各平台产物后调用本脚本。清单与安装包一起上传到
Cloudflare R2；客户端只读取清单，不访问 GitHub API。

用法示例：
    python3 scripts/publish_update_manifest.py \
        --dist dist \
        --version 1.2.3 \
        --build 123 \
        --revision 123456789-1 \
        --notes release-notes.md \
        --base-url https://myxlf.helloswx.top \
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
ARTIFACTS: dict[str, list[str]] = {
    "android": ["MyXLF-{version}.apk"],
    "ios": [
        "MyXLF-{version}.ipa",
        "MyXLF-{version}-unsigned.ipa",
    ],
    "windows": ["MyXLF-{version}-windows-x64.zip"],
    "macos": ["MyXLF-{version}-macos.zip"],
    "linux": ["MyXLF-{version}-linux-x64.tar.gz"],
}


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_manifest(
    *,
    dist: Path,
    version: str,
    build: int,
    base_url: str,
    release_url: str,
    notes: str,
    revision: str = "",
) -> dict:
    base = base_url.rstrip("/")
    # 把构建标识写进路径：同一版本重跑时也不会命中上一轮的 immutable 缓存。
    version_dir = f"releases/v{version}"
    if revision:
        version_dir += f"/{revision}"
    platforms: dict[str, dict] = {}

    for platform, candidates in ARTIFACTS.items():
        for template in candidates:
            name = template.format(version=version)
            path = dist / name
            if not path.is_file():
                continue
            platforms[platform] = {
                "version": version,
                "build": build,
                "url": f"{base}/{version_dir}/{urllib.parse.quote(name)}",
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
