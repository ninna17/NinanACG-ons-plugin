#!/usr/bin/env python3
"""调整上游 app/build.gradle 的构建参数（SDK/NDK 版本、ABI），不触碰任何源码。幂等。"""
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

replacements = [
    (r"compileSdk \d+", "compileSdk 36"),
    (r"ndkVersion '[^']+'", "ndkVersion '27.0.12077973'"),
    (r"buildToolsVersion '[^']+'", "buildToolsVersion '36.0.0'"),
    (r"abiFilters [^\n]+", "abiFilters 'arm64-v8a', 'x86_64'"),
]
for pattern, value in replacements:
    text, count = re.subn(pattern, value, text, count=1)
    if count != 1:
        raise SystemExit(f"未找到要替换的配置: {pattern}")

open(path, "w", encoding="utf-8").write(text)
