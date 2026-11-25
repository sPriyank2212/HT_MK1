import sys, fitz
from PIL import Image
pdf, out = sys.argv[1], sys.argv[2]
a = int(sys.argv[3]) if len(sys.argv) > 3 else 1
n = int(sys.argv[4]) if len(sys.argv) > 4 else 10
cols = int(sys.argv[5]) if len(sys.argv) > 5 else 5
d = fitz.open(pdf)
ims = []
for i in range(a - 1, min(len(d), a - 1 + n)):
    pm = d[i].get_pixmap(dpi=44)
    im = Image.frombytes("RGB", (pm.width, pm.height), pm.samples)
    ims.append(im)
w, h = ims[0].size
rows = (len(ims) + cols - 1) // cols
sh = Image.new("RGB", (w * cols, h * rows), "white")
for i, im in enumerate(ims):
    sh.paste(im, ((i % cols) * w, (i // cols) * h))
sh.save(out)
