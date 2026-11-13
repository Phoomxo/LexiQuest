#!/usr/bin/env python3
"""Deterministic visual-quality audit for the LexiQuest HTML design board.

The audit measures observable proxies for design-system drift and generic-looking
UI.  It does not attempt to identify whether a human or an AI authored a design.
The default mode is report-only; use --strict to make P0/P1 findings fail CI.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from dataclasses import asdict, dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "docs" / "design" / "lexiquest-canva-master-ui.html"
VOID_TAGS = {
    "area",
    "base",
    "br",
    "col",
    "embed",
    "hr",
    "img",
    "input",
    "link",
    "meta",
    "param",
    "source",
    "track",
    "wbr",
}

CANONICAL_TOKENS = {
    "--ink": "#1d2238",
    "--muted": "#5b6275",
    "--primary": "#5046e5",
    "--primary-soft": "#edebff",
    "--mastery": "#0d766e",
    "--mastery-soft": "#d9f2ee",
    "--momentum": "#d98516",
    "--momentum-soft": "#fff1d6",
    "--error": "#ba1a1a",
    "--error-soft": "#ffdad6",
    "--background": "#f5f6fa",
    "--surface": "#ffffff",
    "--border": "#dde1ea",
    "--dark": "#111522",
}

TOKEN_ALIASES = {
    "--mastery": ("--mastery", "--teal"),
    "--mastery-soft": ("--mastery-soft", "--teal-soft"),
    "--momentum": ("--momentum", "--amber"),
    "--momentum-soft": ("--momentum-soft", "--amber-soft"),
    "--background": ("--background", "--bg"),
    "--border": ("--border", "--line"),
}

SCREEN_COMPONENTS = {
    "screen",
    "status",
    "appbar",
    "back",
    "round-icon",
    "greeting",
    "sub",
    "section-label",
    "hero",
    "hero-title",
    "card",
    "row",
    "between",
    "icon",
    "label",
    "value",
    "btn",
    "input",
    "chip",
    "progress",
    "metric",
    "word",
    "pos",
    "choice",
    "feedback",
    "bottomnav",
    "navitem",
    "grid2",
    "tile",
    "fab",
    "switch",
    "avatar",
    "divider",
    "chart",
    "bar",
    "path",
    "node",
    "line",
    "dialog",
    "camera",
    "focus-box",
    "wave",
    "bubble",
    "rail",
    "permission",
    "badge",
    "tiny",
}

INTERACTIVE_COMPONENTS = {
    "back",
    "round-icon",
    "btn",
    "choice",
    "input",
    "fab",
    "navitem",
    "switch",
}

SPACING_PROPERTIES = {
    "gap",
    "row-gap",
    "column-gap",
    "padding",
    "padding-top",
    "padding-right",
    "padding-bottom",
    "padding-left",
    "margin",
    "margin-top",
    "margin-right",
    "margin-bottom",
    "margin-left",
}


@dataclass
class Finding:
    rule_id: str
    severity: str
    category: str
    title: str
    evidence: str
    recommendation: str


@dataclass
class PageMetric:
    label: str
    line: int
    classes: Counter[str] = field(default_factory=Counter)
    text_chars: int = 0
    nested_cards: int = 0


@dataclass
class ScreenMetric:
    page: str
    line: int
    classes: Counter[str] = field(default_factory=Counter)
    text_chars: int = 0


@dataclass
class InlineStyle:
    line: int
    page: str | None
    screen_line: int | None
    classes: tuple[str, ...]
    declarations: dict[str, str]


@dataclass
class Frame:
    tag: str
    classes: set[str]
    is_page: bool = False
    is_screen: bool = False
    is_card: bool = False


class BoardParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[Frame] = []
        self.pages: list[PageMetric] = []
        self.screens: list[ScreenMetric] = []
        self.inline_styles: list[InlineStyle] = []
        self.current_page: PageMetric | None = None
        self.current_screen: ScreenMetric | None = None
        self.lang: str | None = None
        self.viewport: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        data = {key: (value or "") for key, value in attrs}
        classes = set(data.get("class", "").split())
        is_page = tag == "section" and "page" in classes
        is_screen = "screen" in classes
        is_card = "card" in classes

        if tag == "html":
            self.lang = data.get("lang") or None
        if tag == "meta" and data.get("name", "").lower() == "viewport":
            self.viewport = data.get("content") or None

        if is_page:
            self.current_page = PageMetric(
                label=data.get("data-label") or f"page-{len(self.pages) + 1}",
                line=self.getpos()[0],
            )
            self.pages.append(self.current_page)

        if is_screen:
            self.current_screen = ScreenMetric(
                page=self.current_page.label if self.current_page else "unlabelled",
                line=self.getpos()[0],
            )
            self.screens.append(self.current_screen)

        if self.current_page:
            self.current_page.classes.update(classes)
            if is_card and any(frame.is_card for frame in self.stack):
                self.current_page.nested_cards += 1
        if self.current_screen:
            self.current_screen.classes.update(classes)

        if "style" in data:
            self.inline_styles.append(
                InlineStyle(
                    line=self.getpos()[0],
                    page=self.current_page.label if self.current_page else None,
                    screen_line=self.current_screen.line if self.current_screen else None,
                    classes=tuple(sorted(classes)),
                    declarations=parse_declarations(data["style"]),
                )
            )

        if tag not in VOID_TAGS:
            self.stack.append(
                Frame(tag, classes, is_page=is_page, is_screen=is_screen, is_card=is_card)
            )

    def handle_startendtag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag: str) -> None:
        if not self.stack:
            return
        frame = self.stack.pop()
        if frame.is_screen:
            self.current_screen = None
        if frame.is_page:
            self.current_page = None

    def handle_data(self, data: str) -> None:
        visible = len("".join(data.split()))
        if self.current_page:
            self.current_page.text_chars += visible
        if self.current_screen:
            self.current_screen.text_chars += visible


def parse_declarations(body: str) -> dict[str, str]:
    declarations: dict[str, str] = {}
    for chunk in body.split(";"):
        if ":" not in chunk:
            continue
        name, value = chunk.split(":", 1)
        name = name.strip().lower()
        if name:
            declarations[name] = value.strip()
    return declarations


def extract_styles(document: str) -> str:
    return "\n".join(re.findall(r"<style[^>]*>(.*?)</style>", document, re.I | re.S))


def extract_rules(css: str) -> list[tuple[str, dict[str, str]]]:
    clean = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    rules: list[tuple[str, dict[str, str]]] = []
    for match in re.finditer(r"([^{}]+)\{([^{}]*)\}", clean, re.S):
        selector = " ".join(match.group(1).split())
        declarations = parse_declarations(match.group(2))
        if declarations:
            rules.append((selector, declarations))
    return rules


def selector_classes(selector: str) -> set[str]:
    return set(re.findall(r"\.([A-Za-z_][\w-]*)", selector))


def px_values(value: str) -> list[float]:
    return [float(number) for number in re.findall(r"(-?\d+(?:\.\d+)?)px\b", value)]


def first_px(value: str | None) -> float | None:
    if not value:
        return None
    values = px_values(value)
    return values[0] if values else None


def normalized_hex(value: str) -> str | None:
    value = value.strip().lower()
    if re.fullmatch(r"#[0-9a-f]{6}", value):
        return value
    if re.fullmatch(r"#[0-9a-f]{3}", value):
        return "#" + "".join(char * 2 for char in value[1:])
    return None


def relative_luminance(color: str) -> float:
    channels = [int(color[index : index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [
        channel / 12.92
        if channel <= 0.04045
        else ((channel + 0.055) / 1.055) ** 2.4
        for channel in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(foreground: str, background: str) -> float:
    first = relative_luminance(foreground)
    second = relative_luminance(background)
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)


def compact_examples(items: Iterable[str], limit: int = 8) -> str:
    values = list(items)
    shown = values[:limit]
    suffix = f"; และอีก {len(values) - limit} จุด" if len(values) > limit else ""
    return "; ".join(shown) + suffix


def audit(source: Path) -> dict[str, object]:
    document = source.read_text(encoding="utf-8")
    parser = BoardParser()
    parser.feed(document)
    css = extract_styles(document)
    rules = extract_rules(css)
    findings: list[Finding] = []

    root_match = re.search(r":root\s*\{(.*?)\}", css, re.I | re.S)
    tokens = parse_declarations(root_match.group(1)) if root_match else {}

    missing_tokens: list[str] = []
    wrong_tokens: list[str] = []
    alias_only: list[str] = []
    for name, expected in CANONICAL_TOKENS.items():
        actual = normalized_hex(tokens.get(name, ""))
        if actual is None:
            aliases = TOKEN_ALIASES.get(name, (name,))
            alias = next(
                (
                    candidate
                    for candidate in aliases
                    if normalized_hex(tokens.get(candidate, "")) == expected
                ),
                None,
            )
            if alias and alias != name:
                alias_only.append(f"{name}→{alias}")
            else:
                missing_tokens.append(name)
        elif actual != expected:
            wrong_tokens.append(f"{name}={actual} (คาด {expected})")
    if missing_tokens or wrong_tokens or alias_only:
        evidence = []
        if missing_tokens:
            evidence.append("ไม่มี " + ", ".join(missing_tokens))
        if wrong_tokens:
            evidence.append("ค่าต่าง " + ", ".join(wrong_tokens))
        if alias_only:
            evidence.append("ใช้ alias " + ", ".join(alias_only))
        findings.append(
            Finding(
                "TOK-001",
                "P2",
                "design-system",
                "ชื่อ semantic color token ไม่ตรง source of truth",
                "; ".join(evidence),
                "ใช้ชื่อ canonical จาก MASTER.md เพื่อให้ Figma, HTML และ Flutter map บทบาทสีชุดเดียวกัน",
            )
        )

    media_queries = [
        " ".join(query.split())
        for query in re.findall(r"@media\s*([^\{]+)\{", css, re.I)
    ]
    responsive_queries = [
        query
        for query in media_queries
        if "print" not in query.lower()
        and re.search(r"(?:min|max)?-?width|orientation|aspect-ratio", query, re.I)
    ]
    if not responsive_queries:
        findings.append(
            Finding(
                "RSP-001",
                "P1",
                "responsive",
                "artifact ไม่มี compact/medium/expanded breakpoint ที่ตรวจได้",
                f"พบ {len(parser.screens)} mobile screens บน {len(parser.pages)} boards; media query มีเพียง {media_queries or 'ไม่มี'}",
                "เพิ่ม phone และ tablet/foldable frames พร้อมกฎ NavigationBar→NavigationRail และ single-pane→list-detail ที่ breakpoint ระบุชัด",
            )
        )

    component_dimensions: dict[str, dict[str, str]] = {
        name: {} for name in INTERACTIVE_COMPONENTS
    }
    for selector, declarations in rules:
        if re.search(r"::(?:before|after)\b", selector):
            continue
        classes = selector_classes(selector)
        for component in INTERACTIVE_COMPONENTS & classes:
            for prop in ("width", "height", "min-width", "min-height"):
                if prop in declarations:
                    component_dimensions[component][prop] = declarations[prop]

    undersized: list[str] = []
    unverified: list[str] = []
    for component in sorted(INTERACTIVE_COMPONENTS):
        dimensions = component_dimensions[component]
        width = first_px(dimensions.get("min-width") or dimensions.get("width"))
        height = first_px(dimensions.get("min-height") or dimensions.get("height"))
        measured = [value for value in (width, height) if value is not None]
        if measured and min(measured) < 48:
            undersized.append(f".{component}={width or '?'}×{height or '?'}px")
        elif not measured:
            unverified.append(f".{component}")

    inline_undersized: list[str] = []
    for item in parser.inline_styles:
        if not (set(item.classes) & INTERACTIVE_COMPONENTS):
            continue
        height = first_px(item.declarations.get("min-height") or item.declarations.get("height"))
        width = first_px(item.declarations.get("min-width") or item.declarations.get("width"))
        measured = [value for value in (width, height) if value is not None]
        if measured and min(measured) < 48:
            inline_undersized.append(
                f"line {item.line} .{'/'.join(item.classes)}={width or '?'}×{height or '?'}px"
            )
    undersized.extend(inline_undersized)
    if undersized:
        findings.append(
            Finding(
                "A11Y-001",
                "P1",
                "touch",
                "พื้นที่กดบางรายการเล็กกว่า 48dp",
                compact_examples(undersized),
                "ขยาย hit area เป็นอย่างน้อย 48×48dp และคงระยะระหว่างเป้าหมายอย่างน้อย 8dp",
            )
        )
    if unverified:
        findings.append(
            Finding(
                "A11Y-002",
                "P2",
                "touch",
                "องค์ประกอบโต้ตอบบางชนิดไม่มีขนาด hit area ให้ตรวจ",
                ", ".join(unverified),
                "ระบุ min-height/min-width หรือ wrapper hit area 48dp ใน component spec",
            )
        )

    small_type: list[str] = []
    fractional_type: list[str] = []
    for selector, declarations in rules:
        classes = selector_classes(selector)
        if not (classes & SCREEN_COMPONENTS) or "font-size" not in declarations:
            continue
        size = first_px(declarations["font-size"])
        if size is None or size == 0:
            continue
        if size < 12:
            small_type.append(f"{selector}={size:g}px")
        if not size.is_integer():
            fractional_type.append(f"{selector}={size:g}px")
    if small_type:
        findings.append(
            Finding(
                "TYPE-001",
                "P1",
                "typography",
                "ตัวอักษรหน้าจอต่ำกว่า 12sp",
                compact_examples(small_type),
                "ยก label/meta เป็นอย่างน้อย 12sp และทดสอบที่ system font scale 200%",
            )
        )
    if fractional_type:
        findings.append(
            Finding(
                "TYPE-002",
                "P2",
                "typography",
                "type scale มีค่าครึ่งพิกเซลนอก role ที่กำหนด",
                compact_examples(fractional_type),
                "map ทุกข้อความไปยัง Screen task, Screen title, Body หรือ Meta token แทนการปรับทีละครึ่งพิกเซล",
            )
        )

    off_grid: list[str] = []
    for selector, declarations in rules:
        classes = selector_classes(selector)
        if not (classes & SCREEN_COMPONENTS):
            continue
        for prop, value in declarations.items():
            if prop not in SPACING_PROPERTIES:
                continue
            bad = [
                number
                for number in px_values(value)
                if number != 0 and abs(number / 4 - round(number / 4)) > 1e-9
            ]
            if bad:
                off_grid.append(f"{selector} {prop}:{value}")
    for item in parser.inline_styles:
        if item.screen_line is None:
            continue
        for prop, value in item.declarations.items():
            if prop not in SPACING_PROPERTIES:
                continue
            bad = [
                number
                for number in px_values(value)
                if number != 0 and abs(number / 4 - round(number / 4)) > 1e-9
            ]
            if bad:
                off_grid.append(f"line {item.line} {prop}:{value}")
    if off_grid:
        findings.append(
            Finding(
                "SPACE-001",
                "P2" if len(off_grid) >= 5 else "P3",
                "spacing",
                "spacing หลุดกริด 4dp",
                f"พบ {len(off_grid)} declarations: {compact_examples(off_grid)}",
                "แทนค่าทีละจุดด้วย space-1…space-6 และรักษา 20–24dp screen margin, 24–32dp section gap, 8–16dp component gap",
            )
        )

    density_flags: list[str] = []
    for screen in parser.screens:
        cards = screen.classes["card"]
        chips = screen.classes["chip"]
        buttons = screen.classes["btn"]
        surfaces = sum(screen.classes[name] for name in ("card", "tile", "hero", "dialog"))
        reasons = []
        if cards >= 4:
            reasons.append(f"cards={cards}")
        if surfaces >= 5:
            reasons.append(f"surfaces={surfaces}")
        if chips >= 4:
            reasons.append(f"chips={chips}")
        if buttons >= 4:
            reasons.append(f"buttons={buttons}")
        if reasons:
            density_flags.append(
                f"{screen.page} line {screen.line} ({', '.join(reasons)})"
            )
    if density_flags:
        findings.append(
            Finding(
                "DENS-001",
                "P2",
                "hierarchy",
                "บางหน้าจอใช้ container/chip/action มากจนทุกส่วนมีน้ำหนักใกล้กัน",
                compact_examples(density_flags),
                "คง primary action หนึ่งจุด ใช้ whitespace/divider แทน card ที่ไม่จำเป็น และใช้ chip เฉพาะ metadata/filter/status",
            )
        )

    dense_copy = [
        f"{screen.page} line {screen.line} ({screen.text_chars} ตัวอักษร)"
        for screen in parser.screens
        if screen.text_chars > 220
    ]
    if dense_copy:
        findings.append(
            Finding(
                "COPY-001",
                "P2",
                "copy-density",
                "ข้อความบางหน้าจอหนาแน่นเกิน baseline มือถือ",
                compact_examples(dense_copy),
                "ลดข้อความรอง เปิดเผยรายละเอียดแบบ progressive disclosure และทดสอบภาษาไทยที่ 320dp/200% text scale",
            )
        )

    if len(parser.inline_styles) >= max(20, len(parser.screens)):
        property_counts = Counter(
            property_name
            for item in parser.inline_styles
            for property_name in item.declarations
        )
        common = ", ".join(
            f"{name}={count}" for name, count in property_counts.most_common(6)
        )
        findings.append(
            Finding(
                "DRIFT-001",
                "P2",
                "maintainability",
                "inline overrides มากจนเกิด one-off visual decisions",
                f"พบ {len(parser.inline_styles)} style attributes ({common})",
                "ย้ายค่าซ้ำเป็น token/component variant และอนุญาต inline เฉพาะข้อมูลจำเพาะ เช่น progress percentage",
            )
        )

    contrast_checks: list[dict[str, object]] = []
    semantic_values: dict[str, str] = {}
    for canonical in CANONICAL_TOKENS:
        aliases = TOKEN_ALIASES.get(canonical, (canonical,))
        for candidate in aliases:
            value = normalized_hex(tokens.get(candidate, ""))
            if value:
                semantic_values[canonical] = value
                break
    for foreground, background, label in (
        ("--ink", "--background", "ink/background"),
        ("--muted", "--background", "muted/background"),
        ("--muted", "--surface", "muted/surface"),
        ("--surface", "--primary", "surface/primary"),
        ("--surface", "--mastery", "surface/mastery"),
        ("--error", "--error-soft", "error/error-soft"),
    ):
        if foreground not in semantic_values or background not in semantic_values:
            continue
        ratio = contrast_ratio(semantic_values[foreground], semantic_values[background])
        contrast_checks.append(
            {"pair": label, "ratio": round(ratio, 2), "passes_aa_text": ratio >= 4.5}
        )
    failed_contrast = [
        f"{item['pair']}={item['ratio']}:1"
        for item in contrast_checks
        if not item["passes_aa_text"]
    ]
    if failed_contrast:
        findings.append(
            Finding(
                "COLOR-001",
                "P1",
                "contrast",
                "semantic text pair ไม่ผ่าน WCAG AA 4.5:1",
                ", ".join(failed_contrast),
                "ปรับ foreground/background token ก่อนนำไปทำ Figma variables หรือ Flutter ColorScheme",
            )
        )

    severity_points = {"P0": 25, "P1": 14, "P2": 6, "P3": 2}
    risk_score = min(100, sum(severity_points[item.severity] for item in findings))
    if risk_score < 25:
        risk_label = "low"
    elif risk_score < 50:
        risk_label = "medium"
    elif risk_score < 75:
        risk_label = "high"
    else:
        risk_label = "very-high"

    page_metrics = [
        {
            "label": page.label,
            "line": page.line,
            "screens": page.classes["screen"],
            "cards": page.classes["card"],
            "chips": page.classes["chip"],
            "buttons": page.classes["btn"],
            "nested_cards": page.nested_cards,
            "text_chars": page.text_chars,
        }
        for page in parser.pages
    ]
    metrics = {
        "language": parser.lang,
        "viewport": parser.viewport,
        "boards": len(parser.pages),
        "screens": len(parser.screens),
        "cards": sum(page.classes["card"] for page in parser.pages),
        "chips": sum(page.classes["chip"] for page in parser.pages),
        "buttons": sum(page.classes["btn"] for page in parser.pages),
        "inline_styles": len(parser.inline_styles),
        "media_queries": media_queries,
        "responsive_queries": responsive_queries,
        "contrast_checks": contrast_checks,
        "pages": page_metrics,
    }
    return {
        "source": str(source.resolve()),
        "policy_mode": "report-only",
        "authorship_inference": "unsupported; score measures observable design drift only",
        "risk_index": {
            "score": risk_score,
            "label": risk_label,
            "formula": "P0=25, P1=14, P2=6, P3=2; capped at 100",
        },
        "metrics": metrics,
        "findings": [asdict(item) for item in findings],
    }


def render_text(result: dict[str, object]) -> str:
    risk = result["risk_index"]
    metrics = result["metrics"]
    findings = result["findings"]
    lines = [
        "LexiQuest deterministic design audit",
        f"source: {result['source']}",
        f"boards/screens: {metrics['boards']}/{metrics['screens']}",
        f"cards/chips/buttons: {metrics['cards']}/{metrics['chips']}/{metrics['buttons']}",
        f"design-drift risk: {risk['score']}/100 ({risk['label']})",
        "authorship: not inferred (the score is not an AI-authorship probability)",
        f"findings: {len(findings)}",
    ]
    for item in findings:
        lines.extend(
            [
                "",
                f"[{item['severity']}] {item['rule_id']} · {item['title']}",
                f"  evidence: {item['evidence']}",
                f"  fix: {item['recommendation']}",
            ]
        )
    if not findings:
        lines.append("PASS: no deterministic findings")
    return "\n".join(lines)


def main() -> int:
    # Windows commonly inherits a Thai legacy code page; keep CLI/JSON portable.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(
        description="Audit LexiQuest HTML design-system drift deterministically."
    )
    parser.add_argument(
        "source",
        nargs="?",
        type=Path,
        default=DEFAULT_SOURCE,
        help="HTML design board (default: docs/design/lexiquest-canva-master-ui.html)",
    )
    parser.add_argument("--json", action="store_true", help="Emit stable JSON output")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 when P0/P1 findings exist; default remains report-only",
    )
    args = parser.parse_args()
    source = args.source if args.source.is_absolute() else Path.cwd() / args.source
    if not source.is_file():
        parser.error(f"source does not exist: {source}")

    result = audit(source)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(render_text(result))

    if args.strict and any(
        item["severity"] in {"P0", "P1"} for item in result["findings"]
    ):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
