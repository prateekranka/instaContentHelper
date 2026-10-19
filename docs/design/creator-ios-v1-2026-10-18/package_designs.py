from pathlib import Path
import hashlib
import json
from PIL import Image, ImageChops
from reportlab.pdfgen import canvas
from pypdf import PdfReader
import pypdfium2 as pdfium

design = Path(__file__).resolve().parent
project = design.parents[2]
output = project / "output/pdf/contenthelper-creator-ios-screens-2026-10-18.pdf"
evidence = project / "work/evidence/creator-ios-design-2026-10-18"
output.parent.mkdir(parents=True, exist_ok=True)
evidence.mkdir(parents=True, exist_ok=True)
names = [
    "01-first-use", "02-daily-create-approve", "03-plan-review-dates",
    "04-edit-and-versions", "05-film-and-attach", "06-publish-platforms",
    "07-history-safe-edits", "08-you-and-connections",
    "09-day-review-and-recovery", "10-preferences-and-privacy",
]
pdf = canvas.Canvas(str(output))
pdf.setTitle("ContentHelper - Creator iOS screen proposal - 18 October 2026")
pdf.setAuthor("ContentHelper design proposal")
for name in names:
    source = design / f"{name}.png"
    with Image.open(source) as im:
        width, height = im.size
    pdf.setPageSize((width, height))
    pdf.bookmarkPage(name)
    pdf.addOutlineEntry(name.replace("-", " "), name, level=0)
    pdf.drawImage(str(source), 0, 0, width=width, height=height)
    pdf.showPage()
pdf.save()
document = pdfium.PdfDocument(str(output))
results = []
for index, name in enumerate(names):
    source = design / f"{name}.png"
    original = Image.open(source).convert("RGB")
    rendered = document[index].render(scale=1).to_pil().convert("RGB")
    rendered.save(evidence / f"page-{index + 1:02d}.png")
    difference = ImageChops.difference(original, rendered)
    max_difference = max(high for low, high in difference.getextrema())
    width, height = original.size
    bands = []
    for center in [0.135, 0.385, 0.62, 0.87]:
        start, end = int((center - .065) * width), int((center + .065) * width)
        rows = []
        for y in range(int(.72 * height), int(.9 * height)):
            dark = sum(max(original.getpixel((x, y))) < 75 for x in range(start, end))
            if dark / (end - start) > .43:
                rows.append(y)
        runs = []
        for y in rows:
            if not runs or y > runs[-1][-1] + 2:
                runs.append([y])
            else:
                runs[-1].append(y)
        viable = [run for run in runs if 20 <= run[-1] - run[0] <= 80]
        band = max(viable, key=len) if viable else []
        bands.append([band[0], band[-1]] if band else None)
    spread = max(band[0] for band in bands) - min(band[0] for band in bands) if all(bands) else None
    results.append({
        "board": name, "width": width, "height": height,
        "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "pdf_page": index + 1, "pdf_render_max_channel_difference": max_difference,
        "primary_button_dark_bands": bands, "button_top_spread_pixels": spread,
    })
reader = PdfReader(str(output))
report = {"pdf": str(output.relative_to(project)), "pages": len(reader.pages),
          "boards": results, "method": "Static raster review and PDF packaging checks; not app behavior tests"}
(design / "static-measurements.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"pdf": str(output), "pages": len(reader.pages),
                  "pdf_render_max_differences": [item["pdf_render_max_channel_difference"] for item in results],
                  "button_top_spreads": [item["button_top_spread_pixels"] for item in results]}, indent=2))
