"""Read-only pixel inspection of AI part atlases; writes metadata, not image edits."""
from pathlib import Path
from PIL import Image
import json

HERE = Path(__file__).resolve().parent
items = []
for path in sorted(HERE.glob('*.png')):
    image = Image.open(path)
    alpha = image.getchannel('A') if 'A' in image.getbands() else None
    info = {'file': path.name, 'mode': image.mode, 'size': list(image.size)}
    if alpha is not None:
        histogram = alpha.histogram()
        info.update(alpha_bounds=alpha.getextrema(), content_bbox=alpha.getbbox(),
                    transparent_fraction=round(histogram[0]/(image.width*image.height), 5),
                    partially_transparent_pixels=sum(histogram[1:255]))
        bands = []
        for slot in range(3):
            left, right = round(image.width*slot/3), round(image.width*(slot+1)/3)
            bbox = alpha.crop((left, 0, right, image.height)).getbbox()
            bands.append({'slot': slot+1, 'local_bbox': bbox})
        info['three_column_bounds'] = bands
    items.append(info)
(HERE/'alpha-inspection.json').write_text(json.dumps(items, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(items, ensure_ascii=False, indent=2))
