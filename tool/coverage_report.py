"""按文件汇总 lcov.info 的行覆盖率。

用法：先 `flutter test --coverage`，再
`python tool/coverage_report.py`
"""

import collections
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LCOV = os.path.join(ROOT, "coverage", "lcov.info")

cur = None
hit = collections.Counter()
tot = collections.Counter()

with open(LCOV, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.strip()
        if line.startswith("SF:"):
            path = line[3:].replace("\\", "/")
            marker = "/songquery-flutter/"
            cur = path.split(marker)[-1] if marker in path else path
        elif line.startswith("DA:"):
            _, rest = line.split(":", 1)
            _, count = rest.split(",")[:2]
            tot[cur] += 1
            if int(count) > 0:
                hit[cur] += 1

rows = sorted(
    ((hit[f] / tot[f] * 100 if tot[f] else 0.0, hit[f], tot[f], f) for f in tot),
    reverse=True,
)
print(f"{'file':36s} {'cover':>7s}  hit/total")
for pct, h, t, f in rows:
    print(f"{f:36s} {pct:6.1f}%  {h}/{t}")

H, T = sum(hit.values()), sum(tot.values())
print(f"\n{'TOTAL':36s} {H / T * 100:6.1f}%  {H}/{T}")
