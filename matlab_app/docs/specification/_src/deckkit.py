"""仕様書の PowerPoint で使う部品（表紙・カード・枠・画面の画像・矢印・まとめ）。

色・文字・位置の基本は docs/kernel_guide/_src/pptkit.py（技術レポートPowerPoint の見た目）をそのまま使い、
ここには仕様書に要る部品だけを足す。座標はインチ（スライドは 13.333 × 7.5）。
"""
from __future__ import annotations

import math
import os
import sys
from pathlib import Path

from PIL import Image
from pptx import Presentation
from pptx.enum.dml import MSO_LINE_DASH_STYLE
from pptx.util import Inches

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / "kernel_guide" / "_src"))
from pptkit import (BODY, CORAL, CORAL_TINT, GOLD, GOLD_TINT, INK, JP, LIGHT, LIGHT2, LINE, MUTED, NAVY,  # noqa: E402,F401
                    NAVY_PANEL, PANEL, PURPLE, PURPLE_TINT, TEAL, TEAL_TINT, WHITE, background, box, chrome, circle,
                    line, point_bar, table, text)

IMAGES = HERE.parent / "images"
DEFAULT_REFERENCE = Path.home() / ".claude/skills/artifact-template-powerpoint-2/assets/reference.pptx"
ACCENTS = [(CORAL, CORAL_TINT), (TEAL, TEAL_TINT), (PURPLE, PURPLE_TINT), (GOLD, GOLD_TINT)]
CONTENT_LEFT = 0.6
CONTENT_WIDTH = 12.13
FULL_WIDTH_CHAR = 1.0     # 全角 1 文字の幅（文字の大きさに対する比）
HALF_WIDTH_CHAR = 0.55    # 半角 1 文字の幅
LINE_HEIGHT = 1.45        # 1 行の高さ（文字の大きさに対する比）
TITLE_SIZE = 28           # 題名の文字の大きさ（pptkit.chrome と同じ）
TITLE_FIT_WIDTH = 11.4    # 題名が 1 行に収まるかを見る幅 [in]（箱の幅 12.13 より少し狭くして、折り返しを早めに見つける）
AUTO_SIZES = (13, 12.5, 12, 11.5, 11, 10.5, 10)   # heading_blocks の size="auto" で試す文字の大きさ（大きい順）


class Deck:
    """参照デッキ（技術レポートPowerPoint）のマスター・テーマ・フォントを使い、元のスライドを外して新しく置く"""

    def __init__(self, name: str, title: str, reference: Path = DEFAULT_REFERENCE):
        self.name = name
        self.prs = Presentation(str(reference))
        self.prs.core_properties.title = title
        self.prs.core_properties.subject = "面内推定評価ツール（MATLAB アプリ）"
        self.prs.core_properties.author = ""
        self.prs.core_properties.last_modified_by = ""
        use_theme_font(self.prs, JP)
        self.layout = self.prs.slides[0].slide_layout
        id_list = self.prs.slides._sldIdLst
        for slide_id in list(id_list):
            self.prs.part.drop_rel(slide_id.rId)
            id_list.remove(slide_id)
        self.page = 0
        self.long_titles = []

    def slide(self, dark=False):
        slide = self.prs.slides.add_slide(self.layout)
        for placeholder in list(slide.placeholders):
            placeholder._element.getparent().remove(placeholder._element)
        background(slide, NAVY if dark else WHITE)
        self.page += 1
        return slide

    def body(self, chapter: str, title: str):
        slide = self.slide()
        chrome(slide, chapter, title, self.page, self.name)
        if text_lines(title, TITLE_FIT_WIDTH, TITLE_SIZE) > 1:
            print(f"⚠ {self.page} 枚目の題名が 2 行になります：{title}")
            self.long_titles.append(self.page)
        return slide

    def save(self, output: Path):
        """別名（.building.pptx）に書いてから置き換える。PowerPoint で開いている（~$ のロックがある）ときは止める"""
        lock = output.with_name("~$" + output.name)
        if lock.exists():
            raise RuntimeError(f"PowerPoint で開いています。閉じてからやり直してください：{output}")
        building = output.with_suffix(".building.pptx")
        self.prs.save(str(building))
        os.replace(building, output)


def use_theme_font(prs, font: str):
    """テーマの見出し・本文のフォント（英字・日本語）を font にする（文字に直接フォントを付けない所も同じフォントにする）"""
    import re
    for master in prs.slide_masters:
        for rel in master.part.rels.values():
            if not rel.reltype.endswith("/theme"):
                continue
            part = rel.target_part
            xml = part.blob.decode("utf-8")
            xml = re.sub(r'(<a:(?:major|minor)Font>\s*<a:latin typeface=")[^"]*(")', r"\g<1>" + font + r"\g<2>", xml)
            xml = re.sub(r'(<a:(?:major|minor)Font>\s*<a:latin[^>]*/>\s*<a:ea typeface=")[^"]*(")', r"\g<1>" + font + r"\g<2>", xml)
            xml = re.sub(r'(<a:font script="Jpan" typeface=")[^"]*(")', r"\g<1>" + font + r"\g<2>", xml)
            part._blob = xml.encode("utf-8")


def text_lines(content: str, width_in: float, size: float) -> int:
    """文字の箱に入れたときのおおよその行数（全角・半角の幅で数える）"""
    capacity = max(width_in * 72 / size, 1)
    total = 0
    for paragraph in content.split("\n"):
        units = sum(HALF_WIDTH_CHAR if ord(ch) < 0x2E80 else FULL_WIDTH_CHAR for ch in paragraph)
        total += max(1, math.ceil(units / capacity))
    return total


def text_height(content: str, width_in: float, size: float) -> float:
    return text_lines(content, width_in, size) * size * LINE_HEIGHT / 72 + 0.08


def arrow(slide, x1, y1, x2, y2, color=MUTED, dashed=False, width=1.25, head=True):
    connector = line(slide, x1, y1, x2, y2, color=color, width=width, arrow=head)
    if dashed:
        connector.line.dash_style = MSO_LINE_DASH_STYLE.DASH
    return connector


def elbow(slide, points, color=MUTED, dashed=False, width=1.25):
    """折れ線の矢印（最後の区間にだけ矢じり）"""
    for index in range(len(points) - 1):
        (x1, y1), (x2, y2) = points[index], points[index + 1]
        arrow(slide, x1, y1, x2, y2, color=color, dashed=dashed, width=width, head=index == len(points) - 2)


def node(slide, x, y, w, h, label, fill=WHITE, color=INK, size=13, bold=True, line_color=LINE, rounded=True):
    box(slide, x, y, w, h, fill=fill, line=line_color, rounded=rounded)
    text(slide, x + 0.05, y, w - 0.1, h, label, size=size, color=color, bold=bold, align="c", anchor="m")


def tag(slide, x, y, w, content, size=10, color=MUTED, align="c", h=0.3, bold=False):
    text(slide, x, y, w, h, content, size=size, color=color, align=align, anchor="m", bold=bold)


def card(slide, x, y, w, h, color, number, heading, body, size=12, heading_size=15):
    """丸の番号・太字の見出し・本文のカード（白地・細い枠）"""
    box(slide, x, y, w, h, fill=WHITE, line=LINE)
    circle(slide, x + 0.22, y + 0.22, 0.48, color, number, size=13)
    text(slide, x + 0.85, y + 0.2, w - 1.05, 0.52, heading, size=heading_size, color=INK, bold=True, anchor="m")
    text(slide, x + 0.22, y + 0.86, w - 0.44, h - 0.98, body, size=size, color=BODY, line_spacing=1.1)


def panel(slide, x, y, w, h, heading, lines, fill=PANEL, size=12, heading_size=14, bullets=True, heading_color=INK):
    """見出しと箇条書きの枠（淡い地）"""
    box(slide, x, y, w, h, fill=fill)
    text(slide, x + 0.2, y + 0.12, w - 0.4, 0.4, heading, size=heading_size, color=heading_color, bold=True)
    text(slide, x + 0.2, y + 0.55, w - 0.4, h - 0.62, lines, size=size, color=BODY, bullets=bullets, space_after=3)


def blocks_height(blocks, w, size, gap):
    return sum(0.32 + text_height(body, w - 0.1, size) + gap for _, body in blocks)


def heading_blocks(slide, x, y, w, blocks, heading_size=13, size=12, gap=0.12, heading_color=INK, max_y=6.9):
    """見出し（太字）と本文の組を上から並べる。置いた最後の y を返す（はみ出すときは止める）。
    size="auto" なら、max_y までに収まる最も大きい文字（AUTO_SIZES）にし、見出しはそれより 1 pt 大きくする"""
    if size == "auto":
        size = next((s for s in AUTO_SIZES if y + blocks_height(blocks, w, s, gap) <= max_y), AUTO_SIZES[-1])
        heading_size = size + 1
    for heading, body in blocks:
        text(slide, x, y, w, 0.3, heading, size=heading_size, color=heading_color, bold=True)
        y += 0.32
        h = text_height(body, w - 0.1, size)
        text(slide, x, y, w, h, body, size=size, color=BODY)
        y += h + gap
        if y > max_y:
            raise RuntimeError(f"文字が枠からはみ出します：{heading}")
    return y


def screen(slide, name, x, y, w, caption=None, border=LINE):
    """画面の画像（縦横の比はそのまま）と細い枠・下の説明。置いた画像の高さを返す"""
    path = IMAGES / name
    with Image.open(path) as image:
        ratio = image.height / image.width
    h = w * ratio
    slide.shapes.add_picture(str(path), Inches(x), Inches(y), width=Inches(w))
    box(slide, x, y, w, h, fill=None, line=border, rounded=False)
    if caption:
        text(slide, x, y + h + 0.04, w, 0.3, caption, size=10, color=MUTED)
    return h


def step_circle(slide, x, y, number, color=CORAL, d=0.42, size=12):
    circle(slide, x, y, d, color, str(number), size=size)


def cover(deck, kicker, title, subtitle, lead, foot, image=None, image_caption=None):
    slide = deck.slide(dark=True)
    text(slide, 0.8, 0.9, 6.8, 0.4, kicker, size=14, color=LIGHT)
    text(slide, 0.8, 1.6, 6.9, 1.7, title, size=38, color=WHITE, bold=True, anchor="m")
    text(slide, 0.8, 3.45, 6.8, 0.9, subtitle, size=17, color=LIGHT2)
    text(slide, 0.8, 4.45, 6.6, 1.3, lead, size=14, color=WHITE, line_spacing=1.15)
    text(slide, 0.8, 6.35, 7.0, 0.35, foot, size=11, color=LIGHT)
    if image:
        h = screen(slide, image, 8.0, 1.55, 4.75, border=NAVY_PANEL)
        if image_caption:
            text(slide, 8.0, 1.55 + h + 0.08, 4.75, 0.3, image_caption, size=11, color=LIGHT)
    return slide


def agenda(deck, chapter, title, goal, items):
    """この資料の構成：上のゴールの帯と、章のカード（番号・見出し・説明・ページ）"""
    slide = deck.body(chapter, title)
    box(slide, CONTENT_LEFT, 1.55, CONTENT_WIDTH, 0.62, fill=PANEL)
    circle(slide, 0.78, 1.64, 0.44, NAVY, "◎", size=13)
    text(slide, 1.38, 1.55, 11.2, 0.62, goal, size=14, color=INK, bold=True, anchor="m")
    n = len(items)
    gap = 0.22
    w = (CONTENT_WIDTH - gap * (n - 1)) / n
    for index, (heading, body, pages) in enumerate(items):
        color, _ = ACCENTS[index % len(ACCENTS)]
        x = CONTENT_LEFT + index * (w + gap)
        box(slide, x, 2.45, w, 3.9, fill=WHITE, line=LINE)
        circle(slide, x + 0.25, 2.7, 0.62, color, f"{index + 1:02d}", size=15)
        text(slide, x + 0.25, 3.5, w - 0.5, 0.5, heading, size=17, color=INK, bold=True)
        text(slide, x + 0.25, 4.05, w - 0.5, 1.8, body, size=12, color=BODY, line_spacing=1.1)
        text(slide, x + 0.25, 5.9, w - 0.5, 0.3, pages, size=10, color=MUTED)
    return slide


def closing(deck, title, points, related):
    """まとめ（紺地）：要点のカードと関連資料"""
    slide = deck.slide(dark=True)
    text(slide, 0.6, 0.30, 8.0, 0.30, "まとめ", size=12, color=LIGHT, bold=True)
    text(slide, 0.6, 0.62, 12.13, 0.75, title, size=28, color=WHITE, bold=True, anchor="m")
    n = len(points)
    gap = 0.22
    w = (CONTENT_WIDTH - gap * (n - 1)) / n
    for index, (heading, body) in enumerate(points):
        color, _ = ACCENTS[index % len(ACCENTS)]
        x = CONTENT_LEFT + index * (w + gap)
        box(slide, x, 1.7, w, 3.0, fill=NAVY_PANEL)
        circle(slide, x + 0.25, 1.95, 0.52, color, str(index + 1), size=14)
        text(slide, x + 0.25, 2.62, w - 0.5, 0.5, heading, size=16, color=WHITE, bold=True)
        text(slide, x + 0.25, 3.15, w - 0.5, 1.45, body, size=12, color=LIGHT2, line_spacing=1.1)
    text(slide, 0.6, 5.0, 12.13, 0.35, "関連する資料", size=13, color=LIGHT, bold=True)
    text(slide, 0.6, 5.38, 12.13, 1.5, related, size=12, color=WHITE, bullets=True, space_after=2)
    text(slide, 0.6, 7.08, 4.0, 0.25, deck.name, size=9, color=LIGHT)
    text(slide, 11.73, 7.08, 1.0, 0.25, str(deck.page), size=10, color=LIGHT, align="r")
    return slide
