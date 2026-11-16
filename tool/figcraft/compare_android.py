"""Place unaltered FigCraft and Android captures on one annotated canvas."""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def comparison(design, runtime, title, lines, font_path):
    size = (390, 844)
    if design.size != size:
        raise ValueError(f"FigCraft export must be 390x844, received {design.size}")
    if abs(runtime.width / runtime.height - 390 / 844) > 0.001:
        raise ValueError("Android capture must have the same aspect ratio as FigCraft")
    canvas = Image.new("RGB", (828, 1020), "#edf0f5")
    draw = ImageDraw.Draw(canvas)
    heading = ImageFont.truetype(str(font_path), 23)
    body = ImageFont.truetype(str(font_path), 14)
    draw.text((16, 10), title, font=heading, fill="#171a2b")
    draw.text((16, 48), "FigCraft 21b34eaa", font=body, fill="#38405a")
    draw.text((422, 48), "Flutter Android", font=body, fill="#38405a")
    canvas.paste(design.convert("RGB"), (16, 76))
    canvas.paste(runtime.convert("RGB").resize(size, Image.Resampling.LANCZOS), (422, 76))
    for index, line in enumerate(lines):
        draw.text((16, 930 + index * 22), line, font=body, fill="#38405a")
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    evidence = root / "docs/development/figcraft-v1/evidence"
    font = root / "assets/fonts/NotoSansThai-Variable.ttf"
    if args.self_check:
        red = Image.new("RGB", (390, 844), "red")
        blue = Image.new("RGB", (780, 1688), "blue")
        result = comparison(red, blue, "check", [], font)
        assert result.getpixel((16, 76)) == (255, 0, 0)
        assert result.getpixel((422, 76)) == (0, 0, 255)
        print("Comparison placement and aspect ratio: PASS")
        return
    for name, title in [("home", "ฝึกภาษา"), ("library", "คลังคำศัพท์")]:
        with Image.open(evidence / f"design-{name}.webp") as design:
            with Image.open(args.runtime / f"{name}.png") as runtime:
                result = comparison(
                    design,
                    runtime,
                    title,
                    [
                        f"Source {args.sha}",
                        f"{args.device} | 390x844 logical | font 100%",
                        "Synthetic: การเดินทาง 3 คำ / ของใช้ในครัว 0 คำ / platform ถึงคิว 1 คำ",
                    ],
                    font,
                )
                output = args.runtime / f"{name}-comparison.png"
                result.save(output)
                print(output)


if __name__ == "__main__":
    main()
