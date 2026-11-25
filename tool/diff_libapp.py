import zipfile, hashlib

NEW = r"D:\Ongeki\songquery-flutter\build\app\outputs\flutter-apk\app-release.apk"
OLD = r"D:\WorkBuddy space\outputs\songquery-corner-spacing-0.0.1.apk"


def read_so(p, name="lib/arm64-v8a/libapp.so"):
    with zipfile.ZipFile(p) as z:
        return z.read(name)


a = read_so(OLD)
b = read_so(NEW)
print("len", len(a), len(b))

diff = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
print("diff_bytes", len(diff))
if diff:
    print("first", diff[:12])
    print("last", diff[-6:])
    # group into runs
    runs = []
    start = diff[0]
    prev = diff[0]
    for i in diff[1:]:
        if i - prev > 16:
            runs.append((start, prev))
            start = i
        prev = i
    runs.append((start, prev))
    print("runs", len(runs))
    for s, e in runs[:12]:
        print("  off", hex(s), "-", hex(e), "len", e - s + 1, "| old", a[s:e + 1][:16].hex(), "| new", b[s:e + 1][:16].hex())
