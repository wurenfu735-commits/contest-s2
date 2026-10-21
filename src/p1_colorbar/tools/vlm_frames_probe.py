"""把抽出的视频帧发给通义 qwen3-vl-plus，做一次视觉判读。
用途：AI 分析上板录像/示波器截图等；key 从 DSH 本地凭据库读取，不落盘。
用法：python vlm_frames_probe.py [帧目录] [问题]
"""
import base64
import glob
import json
import os
import re
import sys
import urllib.request

# Windows 中文环境默认 GBK 输出，中文/emoji 会崩，这里强制 UTF-8
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

KEY_FILE = r"D:\dsh-home\.credentials.yaml"
URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
MODEL = "qwen3-vl-plus"

DEFAULT_Q = (
    "这是同一段视频在不同时刻的截图。请客观描述："
    "1) 屏幕上显示的图案与颜色布局；"
    "2) 画面最底部是否有一条特殊颜色的横带，什么颜色；"
    "3) 画面有无异常（撕裂、闪烁痕迹、噪点、缺色）；"
    "4) 各帧之间是否有变化。用中文简洁回答。"
)


def load_key() -> str:
    text = open(KEY_FILE, encoding="utf-8").read()
    m = re.search(r"QWEN_TOKEN_PLAN_CN_API_KEY:\s*(\S+)", text)
    if not m:
        raise SystemExit("QWEN key not found in credentials")
    return m.group(1)


def data_url(path: str) -> str:
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def main() -> None:
    frame_dir = sys.argv[1] if len(sys.argv) > 1 else r"E:\fpga\contest_s2\assets\video_frames"
    question = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_Q

    frames = sorted(glob.glob(os.path.join(frame_dir, "frame_*.png")))
    if not frames:
        raise SystemExit(f"no frames in {frame_dir}")

    # 均匀取 5 帧，避免所有帧都是同一画面
    step = max(1, len(frames) // 5)
    picked = frames[::step][:5]

    content = [{"type": "text", "text": question}]
    for p in picked:
        content.append({"type": "image_url", "image_url": {"url": data_url(p)}})

    body = {
        "model": MODEL,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": 900,
    }
    req = urllib.request.Request(
        URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Authorization": "Bearer " + load_key(), "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    print("frames sent:", ", ".join(os.path.basename(p) for p in picked))
    print("--- answer ---")
    print(data["choices"][0]["message"]["content"])
    print("--- usage ---", data.get("usage"))


if __name__ == "__main__":
    main()
