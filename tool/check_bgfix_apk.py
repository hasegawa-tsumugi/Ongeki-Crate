import hashlib, os, zipfile, sys

NEW = r"D:\Ongeki\songquery-flutter\build\app\outputs\flutter-apk\app-release.apk"
OLD = r"D:\WorkBuddy space\outputs\songquery-corner-spacing-0.0.1.apk"


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def info(p):
    st = os.stat(p)
    return st.st_size, sha256(p)


def scan(p):
    abis = {}
    so = {}
    with zipfile.ZipFile(p) as z:
        bad = z.testzip()
        for e in z.infolist():
            if e.filename.startswith("lib/"):
                parts = e.filename.split("/")
                if len(parts) >= 3:
                    abis.setdefault(parts[1], 0)
                    abis[parts[1]] += e.file_size
                    if parts[-1] == "libapp.so":
                        so["app"] = (e.file_size, e.CRC)
            if e.filename == "assets/flutter_assets/AssetManifest.bin":
                so["manifest"] = (e.file_size, e.CRC)
        names = [e.filename for e in z.infolist()]
    return bad, abis, so, names


n_size, n_hash = info(NEW)
print("NEW", NEW)
print("  size", n_size, "sha256", n_hash)
if os.path.exists(OLD):
    o_size, o_hash = info(OLD)
    print("OLD", os.path.basename(OLD))
    print("  size", o_size, "sha256", o_hash)
    print("  size_same", n_size == o_size, "| hash_same", n_hash == o_hash)

bad, abis, so, names = scan(NEW)
print("  zip_corrupt:", bad)
print("  abis:", abis)
print("  libapp.so size/crc:", so.get("app"))
print("  AssetManifest size/crc:", so.get("manifest"))
print("  mtime libapp:", os.path.getmtime(NEW))

obad, oabis, oso, _ = scan(OLD)
print("  OLD abis:", oabis)
print("  OLD libapp.so size/crc:", oso.get("app"))

# key entries that must not exist in a broken package
for must in ("AndroidManifest.xml", "classes.dex", "resources.arsc"):
    print("  has", must, must in names)
print("  dex_count", sum(1 for n in names if n.startswith("classes") and n.endswith(".dex")))
print("  total_entries", len(names))
