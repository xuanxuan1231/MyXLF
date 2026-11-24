#!/usr/bin/env python3
"""生成应用内置的 Noto Sans SC 中文可变字体子集。

Google 的 Noto Sans SC 完整可变字体约 17 MB，包含 3 万多个字形。
应用只需要简体中文（GBK 字符集）和界面中出现的符号，因此这里用
fontTools 裁剪出一个更小的子集：

* 覆盖 GBK 全部汉字（约 2.1 万，包含 CJK 基本区及常用扩展 A 汉字）；
* 覆盖 ASCII、中文标点、全角字符和界面常用符号；
* 自动收集 lib/ 下源码里出现的所有非 ASCII 字符，避免界面文案缺字；
* 保留 wght 可变轴，因此 400/500/700 等字重都能由同一个文件渲染。

用法：
    python3 scripts/subset_noto_sans_sc.py
    python3 scripts/subset_noto_sans_sc.py --source /path/to/NotoSansSC[wght].ttf

依赖：
    pip install fonttools
"""

from __future__ import annotations

import argparse
import glob
import pathlib
import subprocess
import sys
import tempfile
import urllib.request

# Google Fonts 仓库中的 Noto Sans SC 可变字体。
SOURCE_URL = (
    "https://raw.githubusercontent.com/google/fonts/main/"
    "ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"
)

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "assets" / "fonts" / "NotoSansSC.ttf"

# 界面用到的标点、符号和全角字符。GBK 已包含其中一部分，这里显式补全，
# 避免依赖某个字体版本对符号的覆盖差异。
EXTRA_SYMBOLS = (
    "　、。〃々〈〉《》「」『』【】〔〕〖〗〘〙〚〛〜〝〞〟〰〾〿"
    "–—‘’‛“”„‟…‧﹏·×÷±≈≠≤≥∞√∑∏∫∂∆∇∈∉∩∪⊂⊃⊆⊇⊕⊗⊥∥∠∟⌒"
    "←↑→↓↔↕↖↗↘↙↺↻⇒⇔★☆○●◎◇◆□■△▲▽▼※§¶©®™°′″‰％＄￥€£"
    "０１２３４５６７８９ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ"
    "ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ"
    "！＂＃＄％＆＇（）＊＋，－．／：；＜＝＞？＠［＼］＾＿｀｛｜｝～"
)


def gbk_characters() -> set[str]:
    """枚举 GBK 能解码出的全部字符。"""
    chars: set[str] = set()
    for high in range(0x81, 0xFF):
        for low in range(0x40, 0xFF):
            if low == 0x7F:
                continue
            try:
                chars.add(bytes((high, low)).decode("gbk"))
            except UnicodeDecodeError:
                pass
    return chars


def source_characters() -> set[str]:
    """收集 lib/ 下 Dart 源码里出现的非 ASCII 字符。"""
    chars: set[str] = set()
    for path in glob.glob(str(ROOT / "lib" / "**" / "*.dart"), recursive=True):
        chars.update(pathlib.Path(path).read_text(encoding="utf-8"))
    return {c for c in chars if ord(c) >= 0x20}


def ensure_source(path: pathlib.Path | None) -> pathlib.Path:
    if path is not None:
        return path
    cache = pathlib.Path(tempfile.gettempdir()) / "NotoSansSC[wght].ttf"
    if not cache.exists():
        print(f"下载 Noto Sans SC 可变字体：{SOURCE_URL}")
        urllib.request.urlretrieve(SOURCE_URL, cache)
    return cache


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=pathlib.Path,
        help="本地 NotoSansSC[wght].ttf；省略时自动下载到临时目录",
    )
    args = parser.parse_args()

    source = ensure_source(args.source)
    chars = gbk_characters() | source_characters()
    chars.update(chr(cp) for cp in range(0x20, 0x7F))
    chars.update(EXTRA_SYMBOLS)
    chars = {c for c in chars if ord(c) >= 0x20 and c not in "\r\n\t"}

    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", suffix=".txt", delete=False
    ) as tmp:
        tmp.write("".join(sorted(chars)))
        text_file = tmp.name

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            sys.executable,
            "-m",
            "fontTools.subset",
            str(source),
            f"--text-file={text_file}",
            f"--output-file={OUTPUT}",
            "--name-IDs=*",
            "--name-languages=*",
            "--name-legacy",
            "--glyph-names",
            "--symbol-cmap",
            "--legacy-cmap",
            "--notdef-glyph",
            "--notdef-outline",
            "--recommended-glyphs",
        ],
        check=True,
    )

    print(f"字符数：{len(chars)}")
    print(f"输出：{OUTPUT}（{OUTPUT.stat().st_size / 1024 / 1024:.1f} MB）")


if __name__ == "__main__":
    main()
