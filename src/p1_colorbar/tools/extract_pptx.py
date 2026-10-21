"""提取国一作品 PPT 的全文与关键图片，供 AI 分析其答辩思路。
输出：同目录下 <ppt名>_text.txt 与 <ppt名>_imgs\\*.png
"""
import os
import sys

from pptx import Presentation
from pptx.enum.shapes import MSO_SHAPE_TYPE

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def dump(pptx_path: str, out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    prs = Presentation(pptx_path)
    base = os.path.splitext(os.path.basename(pptx_path))[0]
    img_dir = os.path.join(out_dir, base + "_imgs")
    os.makedirs(img_dir, exist_ok=True)

    lines = [f"# {base}  共 {len(prs.slides)} 页"]
    n_img = 0
    for i, slide in enumerate(prs.slides, 1):
        lines.append(f"\n{'=' * 70}\n[第 {i} 页]")
        for shape in slide.shapes:
            # 文本框
            if shape.has_text_frame:
                for para in shape.text_frame.paragraphs:
                    t = "".join(r.text for r in para.runs).strip()
                    if t:
                        lines.append("  " + t)
            # 表格
            if shape.has_table:
                for row in shape.table.rows:
                    cells = [c.text.strip().replace("\n", " ") for c in row.cells]
                    lines.append("  | " + " | ".join(cells) + " |")
            # 图片
            if shape.shape_type == MSO_SHAPE_TYPE.PICTURE:
                try:
                    img = shape.image
                    n_img += 1
                    fn = os.path.join(img_dir, f"s{i:02d}_{n_img:03d}.{img.ext}")
                    with open(fn, "wb") as f:
                        f.write(img.blob)
                    lines.append(f"  <图片 {n_img}: {os.path.basename(fn)} {len(img.blob)//1024}KB>")
                except Exception as e:
                    lines.append(f"  <图片提取失败: {e}>")
        # 备注
        try:
            if slide.has_notes_slide:
                note = slide.notes_slide.notes_text_frame.text.strip()
                if note:
                    lines.append("  [备注] " + note.replace("\n", " / "))
        except Exception:
            pass

    txt_path = os.path.join(out_dir, base + "_text.txt")
    with open(txt_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"OK {base}: {len(prs.slides)} 页, 导出图片 {n_img} 张")
    print(f"   文本 -> {txt_path}")
    print(f"   图片 -> {img_dir}")


if __name__ == "__main__":
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.dirname(src)
    if os.path.isdir(src):
        for fn in sorted(os.listdir(src)):
            if fn.lower().endswith(".pptx") and not fn.startswith("~$"):
                dump(os.path.join(src, fn), out)
    else:
        dump(src, out)
