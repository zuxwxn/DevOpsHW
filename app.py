from __future__ import annotations

from collections import Counter
from io import BytesIO
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageFile, UnidentifiedImageError

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MiB
MAX_PIXELS = 50_000_000
PALETTE_SIZE = 5

# Pillow should reject images that claim unreasonable pixel counts before decoding.
Image.MAX_IMAGE_PIXELS = MAX_PIXELS
ImageFile.LOAD_TRUNCATED_IMAGES = False

app = FastAPI(title="이미지 대표 색상 추출기")
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/", include_in_schema=False)
async def home() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


def error(message: str, status_code: int = 400) -> HTTPException:
    return HTTPException(status_code=status_code, detail=message)


def load_image(image_bytes: bytes) -> Image.Image:
    """Validate supplied bytes and return a decoded RGB image, without storing it."""
    try:
        with Image.open(BytesIO(image_bytes)) as probe:
            probe.verify()
        with Image.open(BytesIO(image_bytes)) as source:
            source.load()
            # Composite transparent source pixels onto white for predictable colors.
            if source.mode in ("RGBA", "LA") or (source.mode == "P" and "transparency" in source.info):
                rgba = source.convert("RGBA")
                background = Image.new("RGBA", rgba.size, "white")
                background.alpha_composite(rgba)
                return background.convert("RGB")
            return source.convert("RGB")
    except Image.DecompressionBombError as exc:
        raise error("이미지 해상도가 너무 큽니다. 5천만 픽셀 이하의 이미지를 선택해 주세요.") from exc
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError) as exc:
        raise error("손상되었거나 지원하지 않는 이미지입니다. 정상적인 JPG, PNG, WEBP 또는 GIF 파일을 선택해 주세요.") from exc


def extract_palette(image: Image.Image, color_count: int = PALETTE_SIZE) -> list[dict[str, str | int]]:
    """Downsample then use Pillow's median-cut quantizer to find dominant RGB colors."""
    working = image.copy()
    working.thumbnail((600, 600), Image.Resampling.LANCZOS)

    # Quantization on a small RGB image is fast on an ordinary laptop CPU.
    quantized = working.quantize(colors=color_count, method=Image.Quantize.MEDIANCUT)
    counts = Counter(quantized.getdata())
    palette = quantized.getpalette()

    colors: list[dict[str, str | int]] = []
    for index, pixel_count in counts.most_common(color_count):
        offset = index * 3
        red, green, blue = palette[offset : offset + 3]
        colors.append({
            "hex": f"#{red:02X}{green:02X}{blue:02X}",
            "rgb": f"rgb({red}, {green}, {blue})",
            "pixels": pixel_count,
        })
    return colors


@app.post("/api/extract")
async def extract_colors(file: UploadFile = File(...)) -> dict[str, list[dict[str, str | int]]]:
    if not file.filename:
        raise error("파일을 선택해 주세요.")

    # Read only enough to enforce the limit. Data remains in memory for this request only.
    image_bytes = await file.read(MAX_FILE_SIZE + 1)
    await file.close()
    if not image_bytes:
        raise error("빈 파일은 분석할 수 없습니다.")
    if len(image_bytes) > MAX_FILE_SIZE:
        raise error("파일 용량이 너무 큽니다. 10MB 이하의 이미지를 선택해 주세요.", 413)

    image = load_image(image_bytes)
    colors = extract_palette(image)
    if not colors:
        raise error("이미지에서 색상을 추출하지 못했습니다. 다른 이미지를 선택해 주세요.")
    return {"colors": colors}
