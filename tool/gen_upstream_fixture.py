"""生成 test/fixtures/upstream_sample.json —— 转换器的独立预言机样本。

## 为什么需要它

`Dataset.fromUpstream` 把 otoge-db 的扁平字段翻译成领域模型。这份翻译一旦抄错，
**条数不变、格式校验也能过**，用户要到在线更新成功之后才会发现定数全错了。
2026-11-02 就抓到一次：`lev_*_i` 是 `'11.8'` 这种小数形态的字符串，被当成
「定数×10 的整数」用 `~/ 10` 拆，结果全库定数变成 1.1。

所以这里产出一份**真实上游行**，让测试拿它去和 `assets/songs-*.json`
（RN 管线生成的快照，与 Dart 代码无关）逐字段比对。快照是外部期望值，
不是这份代码生出来的，抄错就会红。

## 挑选逻辑

1. 用照抄 RN 原版 `src/sources/ongeki.ts` 的算法把上游行转成曲目；
2. 只保留转出来与快照**逐字段一致**的行 —— 排除「快照日期之后上游改过定数」
   造成的假红；
3. 在通过筛选的行里按边界形态取样（整数难度、LUNATIC 独立条目、缺 bpm、
   缺物量、带 `+` 标签、高难 14.x），再补足总数。

## 用法

    python tool/gen_upstream_fixture.py              # 自动下载上游
    python tool/gen_upstream_fixture.py --source x.json
    python tool/gen_upstream_fixture.py --dry-run    # 只看统计不落盘

换快照（`assets/songs-YYYY.MM.DD.json`）后重跑一次，让期望值跟上。
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

DATA_URLS = [
    'https://fastly.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json',
    'https://cdn.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json',
    'https://gcore.jsdelivr.net/gh/hasegawa-tsumugi/otoge-db@main/ongeki/data/music-ex.json',
]
SUFFIXES = ['bas', 'adv', 'exc', 'mas', 'lnt']
SAMPLE_SIZE = 40

# 哪些字段可以作为期望值。快照里没有的（designer / chartLink / copyright）
# 不参与比对 —— RN 端 undefined 的字段被 JSON.stringify 丢掉了。
SONG_FIELDS = ['id', 'title', 'titleKana', 'artist', 'genre', 'genreId', 'bpm',
               'releaseTag', 'chapter', 'chapterId', 'character', 'characterId',
               'enemyLevel', 'enemyType', 'dateAdded', 'wikiUrl', 'artwork']
CHART_FIELDS = ['difficulty', 'level', 'levelDecimal', 'levelValue',
                'levelLabel', 'noteCount', 'bells']


def as_text(v) -> str:
    if isinstance(v, str):
        return v.strip()
    return '' if v is None else str(v).strip()


def as_num(v) -> float:
    """上游的数字几乎都是字符串，`Number()` 语义：认不出就是 0。"""
    t = as_text(v)
    if not t:
        return 0.0
    try:
        return float(t)
    except ValueError:
        return 0.0


def text_or_none(v):
    t = as_text(v)
    return None if t in ('', '-') else t


def positive_or_none(v):
    n = as_num(v)
    return int(n) if n > 0 else None


def convert(row: dict) -> dict:
    """照抄 RN 原版 src/sources/ongeki.ts 的 toSong / toChart。"""
    charts = []
    for i, s in enumerate(SUFFIXES):
        label = text_or_none(row.get(f'lev_{s}'))
        if not label:
            continue
        value = as_num(row.get(f'lev_{s}_i'))
        known = value > 0
        level = int(value) if known else int(''.join(c for c in label if c.isdigit()) or 0)
        charts.append({
            'difficulty': i,
            'level': level,
            'levelDecimal': round((value - level) * 10) if known else 0,
            'levelValue': value if known else 0,
            'levelLabel': label,
            'noteCount': positive_or_none(row.get(f'lev_{s}_notes')),
            'bells': positive_or_none(row.get(f'lev_{s}_bells')),
        })
    added = text_or_none(row.get('date_added'))
    if added and len(added) == 8 and added.isdigit():
        added = f'{added[:4]}-{added[4:6]}-{added[6:]}'
    bpm = as_num(row.get('bpm'))
    return {
        'id': text_or_none(row.get('id')),
        'title': text_or_none(row.get('title')),
        'titleKana': text_or_none(row.get('title_sort')),
        'artist': text_or_none(row.get('artist')),
        'genre': text_or_none(row.get('category')),
        'genreId': text_or_none(row.get('category_id')),
        'bpm': bpm if bpm > 0 else None,
        'releaseTag': text_or_none(row.get('version')),
        'chapter': text_or_none(row.get('chapter')),
        'chapterId': text_or_none(row.get('chap_id')),
        'character': text_or_none(row.get('character')),
        'characterId': text_or_none(row.get('chara_id')),
        'enemyLevel': positive_or_none(row.get('enemy_lv')),
        'enemyType': text_or_none(row.get('enemy_type')),
        'dateAdded': added,
        'wikiUrl': text_or_none(row.get('wikiwiki_url')),
        'artwork': text_or_none(row.get('image_url')),
        'charts': charts,
    }


def matches(conv: dict, snap: dict) -> bool:
    for f in SONG_FIELDS:
        if conv[f] != snap.get(f):
            return False
    if len(conv['charts']) != len(snap['charts']):
        return False
    for a, b in zip(conv['charts'], snap['charts']):
        for f in CHART_FIELDS:
            if a[f] != b.get(f):
                return False
    return True


def fetch(urls: list[str]) -> list[dict]:
    """下载上游。用 curl 而不是 urllib：这台机器上 curl 的代理/TLS 配置更省心。"""
    for url in urls:
        print(f'  下载 {url}')
        try:
            out = subprocess.run(
                ['curl', '-sS', '--max-time', '120', url],
                capture_output=True, check=True,
            ).stdout
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            print(f'    失败：{e}')
            continue
        if not out:
            print('    空响应')
            continue
        print(f'    收到 {len(out):,} 字节')
        return json.loads(out.decode('utf-8'))
    sys.exit('所有上游线路都拿不到数据')


def pick(good: list[tuple[dict, dict, dict]]) -> list[dict]:
    """按边界形态取样，不是随便取前 N 行。"""
    buckets = [
        ('整数难度（无小数）',
         lambda c: any(ch['level'] > 0 and ch['levelValue'] == 0 for ch in c['charts'])),
        ('全部难度都没有小数',
         lambda c: not any(ch['levelValue'] > 0 for ch in c['charts'])),
        ('只有 LUNATIC',
         lambda c: [ch['difficulty'] for ch in c['charts']] == [4]),
        ('缺 bpm', lambda c: c['bpm'] is None),
        ('有谱面缺物量', lambda c: any(ch['noteCount'] is None for ch in c['charts'])),
        ('标签带 +', lambda c: any(ch['levelLabel'].endswith('+') for ch in c['charts'])),
        ('高难 14.x', lambda c: any(ch['levelValue'] >= 14 for ch in c['charts'])),
    ]
    picked, seen = [], set()

    def take(pred, limit):
        n = 0
        for row, conv, _ in good:
            if n >= limit:
                break
            if conv['id'] in seen or not pred(conv):
                continue
            seen.add(conv['id'])
            picked.append(row)
            n += 1

    for name, pred in buckets:
        before = len(picked)
        take(pred, 4)
        print(f'  {name:<18} +{len(picked) - before}')
    take(lambda c: True, max(0, SAMPLE_SIZE - len(picked)))
    return picked


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(here)
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', help='本地上游 json；不给就从三条 CDN 线路下载')
    ap.add_argument('--snapshot', default='assets/songs-2026.10.15.json')
    ap.add_argument('--out', default='test/fixtures/upstream_sample.json')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    if args.source:
        with open(args.source, encoding='utf-8') as f:
            rows = json.load(f)
    else:
        rows = fetch(DATA_URLS)
    rows = rows['songs'] if isinstance(rows, dict) else rows

    with open(args.snapshot, encoding='utf-8') as f:
        snapshot = {s['id']: s for s in json.load(f)['songs']}
    print(f'上游 {len(rows)} 行 / 快照 {len(snapshot)} 首')

    good = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        conv = convert(row)
        ref = snapshot.get(conv['id'])
        if ref and matches(conv, ref):
            good.append((row, conv, ref))
    print(f'与快照逐字段一致：{len(good)} / {len(rows)}')

    if len(good) < SAMPLE_SIZE:
        sys.exit('可用的行太少：快照可能太旧（上游改了定数），或转换逻辑已经漂移')

    picked = pick(good)
    convs = [convert(r) for r in picked]
    zero = sum(1 for c in convs if not any(ch['levelValue'] > 0 for ch in c['charts']))
    ratio = zero / max(1, len(convs))
    print(f'样本 {len(picked)} 条，其中无正 levelValue {zero} 条（{ratio * 100:.1f}%）')
    if ratio > 0.2:
        sys.exit('样本比例会踩响「无正 levelValue」护栏（上限 20%），减少该类样本')

    if args.dry_run:
        print('--dry-run：不落盘')
        return
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(picked, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'已写出 {args.out}（{os.path.getsize(args.out):,} 字节）')


if __name__ == '__main__':
    main()
