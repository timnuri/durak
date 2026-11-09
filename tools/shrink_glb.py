#!/usr/bin/env python3
"""Уменьшает текстуры внутри .glb (чтобы APK и браузерная версия были лёгкими).
python3 tools/shrink_glb.py in.glb out.glb [макс_сторона=1024]"""
import io, json, struct, sys
from PIL import Image

def load(p):
    b = open(p, 'rb').read(); off = 12; js = None; bn = b''
    while off < len(b):
        ln, typ = struct.unpack('<I4s', b[off:off + 8]); ch = b[off + 8:off + 8 + ln]
        if typ == b'JSON': js = json.loads(ch)
        else: bn = ch
        off += 8 + ln
    return js, bn

def main(src, dst, mx):
    j, bn = load(src)
    views = j['bufferViews']
    data = [bn[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']] for v in views]
    for im in j.get('images', []):
        k = im['bufferView']; I = Image.open(io.BytesIO(data[k])); I.load()
        s = min(1.0, mx / max(I.size))
        if s < 1.0: I = I.resize((max(1, round(I.size[0] * s)), max(1, round(I.size[1] * s))), Image.LANCZOS)
        out = io.BytesIO()
        alpha = I.mode in ('RGBA', 'LA', 'P') and I.convert('RGBA').getextrema()[3][0] < 255
        if im['mimeType'] == 'image/webp': I.save(out, 'WEBP', quality=88)
        elif alpha: I.save(out, 'PNG', optimize=True)
        else: I.convert('RGB').save(out, 'JPEG', quality=88); im['mimeType'] = 'image/jpeg'
        data[k] = out.getvalue()
    blob = b''
    for v, d in zip(views, data):
        while len(blob) % 4: blob += b'\0'
        v['byteOffset'] = len(blob); v['byteLength'] = len(d); v['buffer'] = 0
        blob += d
    while len(blob) % 4: blob += b'\0'
    j['buffers'] = [{'byteLength': len(blob)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    out = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<I4s', len(js), b'JSON') + js + struct.pack('<I4s', len(blob), b'BIN\0') + blob
    open(dst, 'wb').write(out)
    print(dst, len(out) // 1024, 'KB')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1024)
