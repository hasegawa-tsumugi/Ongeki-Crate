"""浅色主题下实测「选项类」控件的计算样式与对比度。

用真实 Chrome + getComputedStyle 取值，再按 WCAG 相对亮度算对比度 ——
比在源码里 grep 颜色字符串可靠（`.select` / `.circle` 就曾被后面的覆盖规则
救回来过，只看第一条 `.select{}` 会得出错误结论）。

用法：
    python tool/check_light_contrast.py [绝对路径 | file:/http 链接]
    （不传则量真实构建产物 D:/WorkBuddy space/outputs/songquery-webapp/index.html）

参数可以是相对项目根的路径、绝对路径或完整 URL —— 之前一律按「相对项目根」拼，
传绝对路径会拼成一个不存在的 URL，量到的是空白页的浏览器底色，结论全废。
"""

import re
import sys
import urllib.parse

sys.path.insert(0, "D:/Ongeki/songquery-flutter/build")

import cdp  # noqa: E402

STYLE_CHIP = (
    "(() => { const c = document.querySelector('#filterGroups .chip');"
    " if (!c) return ['none']; const s = getComputedStyle(c);"
    " return [s.color, s.backgroundColor, c.textContent]; })()"
)
STYLE_CHIP_ON = (
    "(() => { const c = document.querySelector('#filterGroups .chip[aria-pressed=true]');"
    " if (!c) return ['none']; const s = getComputedStyle(c);"
    " return [s.color, s.backgroundColor, c.textContent]; })()"
)

STYLE_HEADING = (
    "(() => { const h = document.querySelector('#filterGroups .group h3');"
    " if (!h) return ['none']; const s = getComputedStyle(h);"
    # 标题直接落在画布上，给个全透明底让 measure 合成到页面底色。
    " return [s.color, 'rgba(0,0,0,0)', h.textContent]; })()"
)

# 排序三栏：分别对应表格的茶/绿/蓝三组（主排序与难度条件都已下线）。
STYLE_DSORT = (
    "(() => { const s = document.getElementById('tabGroupSel');"
    " if (!s) return ['none']; const c = getComputedStyle(s);"
    " return [c.color, c.backgroundColor, s.value || s.textContent]; })()"
)

EXPRS = [
    # 必须显式写成浅色：新版本默认跟随系统，移除属性只会回到 JS 里「跟随偏好」的分支，
    # 在深色系统上量出来的是深色主题（曾经因此报 KeyError 且结论无效）。
    "(() => { document.documentElement.dataset.theme='light';"
    " try { localStorage.setItem('songquery.themeMode','light'); } catch (e) {}"
    " return 'light'; })()",
    "document.querySelectorAll('.screen').forEach(s => s.classList.add('hidden')),"
    "document.getElementById('s-search').classList.remove('hidden'),"
    "typeof renderSearch === 'function' ? (renderSearch(), 'rendered') : 'no-fn'",
    "document.querySelectorAll('#filterGroups .chip').length",
    STYLE_CHIP,
    STYLE_HEADING,
    "(() => { const e = document.getElementById('tabGroupSel');"
    " if (!e) return ['none']; const s = getComputedStyle(e);"
    " return [s.color, s.backgroundColor]; })()",
    "(() => { const c = document.querySelector('.circle'); if (!c) return ['none'];"
    " const s = getComputedStyle(c); return [s.color, s.backgroundColor]; })()",
    "getComputedStyle(document.body).backgroundColor",
    # 点一下第一个标签再取选中态；renderSearch 会重建 DOM，必须重新查询。
    "(document.querySelector('#filterGroups .chip').click(), 'clicked')",
    STYLE_CHIP_ON,
    "(() => { if (typeof renderSearch !== 'function') return false;"
    " renderSearch(); return !!document.getElementById('tabGroupSel'); })()",
    STYLE_DSORT,
]


def parse(css_color):
    nums = css_color.replace("rgba(", "").replace("rgb(", "").replace(")", "")
    parts = [float(x) for x in nums.split(",")]
    return parts[0], parts[1], parts[2], (parts[3] if len(parts) > 3 else 1.0)


def lum(rgb):
    def ch(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    return 0.2126 * ch(rgb[0]) + 0.7152 * ch(rgb[1]) + 0.0722 * ch(rgb[2])


def ratio(fg, bg):
    l1, l2 = lum(fg), lum(bg)
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)


def to_url(page):
    """相对项目根的路径 / 绝对路径 / 完整 URL 都要能跑。

    以前一律当相对路径拼，传绝对路径会拼成不存在的 URL，量到的是空白页底色。
    """
    if page.startswith(("file:", "http:", "https:")):
        return page
    if re.match(r"^[A-Za-z]:[\\/]", page) or page.startswith(("/", "\\")):
        path = page.replace("\\", "/").lstrip("/")
        return "file:///" + urllib.parse.quote(path, safe="/:")
    return f"file:///D:/Ongeki/songquery-flutter/{page}"


def main():
    # 默认指向真实构建产物。以前默认 `build/webapp.html` —— 那是 11-21 一次
    # 手工拷贝留下的快照，早就不含三栏下拉，脚本却一直「ALL PASS」。
    page = (sys.argv[1] if len(sys.argv) > 1
            else "D:/WorkBuddy space/outputs/songquery-webapp/index.html")
    proc, ws = cdp.start(to_url(page), 500, 1000)
    try:
        out = cdp.ws_send(ws, EXPRS)
    finally:
        proc.terminate()

    theme, _, count, chip, heading, sel, circle, body, _, chip_on, diff_on, dsort = out
    print(f"page={page} theme={theme} chips={count}")
    print("body:", body)
    page_rgb = parse(body)[:3]
    if lum(page_rgb) < 0.5:
        # 深色底上算出来的对比度毫无意义 —— 与其给个假结论，不如直接判失败。
        print("[FAIL] 页面没渲染成浅色（路径错了 / 页面空白 / 主题没切过来），测量结果无效")
        return 1

    def measure(name, value, threshold, required=False):
        if not isinstance(value, list):
            # 取值表达式抛错时 cdp 会把错误对象塞回来，别当成「没有这个控件」跳过。
            print(f"[FAIL] {name}: 取值失败 {value}")
            return False
        if not value or value[0] == "none":
            # 三栏下拉是常显控件：量不到就说明页面是旧版本、或者选择器改过。
            # 以前这里一律 [SKIP]，于是默认读的那个 11-21 旧快照（页面里根本
            # 没有 tabGroupSel）连年「ALL PASS」，排序下拉实际一项都没测。
            if required:
                print(f"[FAIL] {name}: 页面上找不到这个控件（旧版本页面 / 选择器过期？）")
                return False
            print(f"[SKIP] {name}")
            return True
        fg = parse(value[0])[:3]
        bg = parse(value[1])
        bg = (tuple(bg[i] * bg[3] + page_rgb[i] * (1 - bg[3]) for i in range(3))
              if bg[3] < 1 else bg[:3])
        r = ratio(fg, bg)
        ok = r >= threshold
        label = value[2] if len(value) > 2 else ""
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: 文字 {value[0]} / 底 {value[1]} "
              f"→ {r:.2f}:1（阈值 {threshold}）「{label}」")
        return ok

    ok = all([
        measure("筛选 chip（未选）", chip, 4.5),
        measure("分组标题（洋红）", heading, 3.0),
        measure("排序三栏下拉", sel, 4.5, required=True),
        measure("底部圆钮", circle, 4.5),
        # 选中白字与标题保留原洋红；3.0 仅为回归阈值，不表示正文 AA 达标。
        measure("筛选 chip（选中）", chip_on, 3.0),
        measure("排序三栏取值", dsort, 4.5, required=True),
    ])
    print("\nALL PASS" if ok else "\nFAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
