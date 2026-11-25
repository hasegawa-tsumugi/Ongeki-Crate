# -*- coding: utf-8 -*-
"""统计曲名 / 作者里「不可断单元」的长度分布。

用来决定「整词换行」这件事到底有多少首会受影响：只要一个拉丁/数字连成的
单元比行宽还宽，Flutter 就会在单词中间硬断（GO!GO! -> GO!G / O!）。
日文、中文每个字都可以断，所以只统计非 CJK 的连续段。
"""
import json
import re
import sys
from collections import Counter

CJK = (
    r"\u3000-\u303f"  # CJK 标点
    r"\u3040-\u309f"  # 平假名
    r"\u30a0-\u30ff"  # 片假名
    r"\u3400-\u4dbf"
    r"\u4e00-\u9fff"  # 汉字
    r"\uf900-\ufaff"
    r"\uff00-\uffef"  # 全角标点
)


def longest_run(text: str) -> str:
    runs = re.findall(rf"[^{CJK}\s]+", text or "")
    return max(runs, key=len) if runs else ""


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else "assets/songs-2026.10.15.json"
    data = json.load(open(path, encoding="utf-8"))
    songs = data["songs"]
    for field in ("title", "artist"):
        counter = Counter()
        worst = []
        for song in songs:
            run = longest_run(song.get(field) or "")
            counter[len(run)] += 1
            worst.append((len(run), run, song.get("title")))
        longest = sorted(worst, reverse=True)[:8]
        over = [w for w in worst if w[0] >= 9]
        print(f"[{field}] 总 {len(songs)} 条，最长单元 >=9 字符的有 {len(over)} 条")
        hist = {n: counter[n] for n in sorted(counter) if n >= 6}
        print("  长度分布(>=6):", hist)
        for n, run, title in longest:
            print(f"  {n:>3} {run!r}  <- {title!r}")
        print()


if __name__ == "__main__":
    main()
