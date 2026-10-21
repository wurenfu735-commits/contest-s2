#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
上传前/上传后核对：本地 HEAD 的树  vs  GitHub 远程分支的树，逐文件比 blob 哈希。

为什么要这个脚本
----------------
"git push 成功" 不等于 "远程内容是对的"；"GitHub 上能看到文件" 也不等于 "字节一致"。
本脚本把核对做成机械动作：文件数、每个文件的 blob 哈希、位流大小全对上才算 PASS。

用法
----
    python tools/verify_remote.py                    # 比 origin/main
    python tools/verify_remote.py --branch b4-osd    # 比别的分支
    python tools/verify_remote.py --deep             # 额外把 bitbank 里的位流整块拉下来算 md5

退出码：0 = 完全一致；1 = 有差异（差异会逐条列出）。

说明
----
- 仓库当前是 public，所以**匿名 GET 就够**，脚本不需要 token。
  （若以后改回 private，设环境变量 GH_TOKEN 即可，脚本会自动带上。）
- 只读，不写远程，任何情况下都可以放心跑。
- 走的是 api.github.com，所以哪怕 github.com:443 被网络挡了（git push 不通）也能核对。
"""

import argparse
import hashlib
import json
import os
import ssl
import subprocess
import sys
import urllib.request

OWNER = "wurenfu735-commits"
REPO = "contest-s2"
API = f"https://api.github.com/repos/{OWNER}/{REPO}"
CTX = ssl.create_default_context()


def gh(path):
    # GitHub API 的响应带 Cache-Control: max-age=60，走代理/中间层时会被缓存，
    # 导致"刚推上去却读到旧 ref"——所以统一加 no-cache + 时间戳参数打掉缓存。
    import time
    url = API + path if path.startswith("/") else path
    if "?" in url:
        url += f"&_={int(time.time() * 1000)}"
    else:
        url += f"?_={int(time.time() * 1000)}"
    req = urllib.request.Request(url)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "verify-remote")
    req.add_header("Cache-Control", "no-cache")
    req.add_header("Pragma", "no-cache")
    tok = os.environ.get("GH_TOKEN")
    if tok:
        req.add_header("Authorization", f"Bearer {tok}")
    with urllib.request.urlopen(req, timeout=120, context=CTX) as r:
        return json.loads(r.read().decode())


def remote_tree(branch):
    ref = gh(f"/git/ref/heads/{branch}")
    commit = ref["object"]["sha"]
    tree = gh(f"/git/trees/{ref['object']['sha']}?recursive=1")
    if tree.get("truncated"):
        print("⚠️  远程树被截断（>10 万条目），核对不完整")
    files = {}
    for e in tree["tree"]:
        if e["type"] == "blob":
            files[e["path"]] = (e["mode"], e["sha"], e.get("size", -1))
    return commit, files


def local_tree(rev):
    out = subprocess.run(["git", "ls-tree", "-r", "-z", rev],
                         capture_output=True, check=True).stdout
    files = {}
    for rec in out.split(b"\0"):
        if not rec:
            continue
        meta, path = rec.split(b"\t", 1)
        mode, typ, sha = meta.decode().split()
        files[path.decode("utf-8", "surrogateescape")] = (mode, sha, -1)
    return files


def blob_md5(sha):
    raw = gh(f"/git/blobs/{sha}")
    import base64
    data = base64.b64decode(raw["content"])
    return len(data), hashlib.md5(data).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--branch", default="main")
    ap.add_argument("--rev", default="HEAD", help="本地要比的 revision，默认 HEAD")
    ap.add_argument("--deep", action="store_true", help="下载 bitbank 位流并算 md5")
    args = ap.parse_args()

    print(f"仓库   : {OWNER}/{REPO}")
    print(f"本地   : {args.rev}  ({(subprocess.run(['git','rev-parse','--short',args.rev],capture_output=True,text=True).stdout.strip())})")
    print(f"远程   : {args.branch}")

    commit, rem = remote_tree(args.branch)
    loc = local_tree(args.rev)
    print(f"远程 HEAD: {commit}")
    print(f"文件数   : 本地 {len(loc)} / 远程 {len(rem)}")
    print()

    only_local = sorted(set(loc) - set(rem))
    only_remote = sorted(set(rem) - set(loc))
    diff = sorted(p for p in set(loc) & set(rem) if loc[p][1] != rem[p][1])

    ok = not (only_local or only_remote or diff)

    if only_local:
        print(f"❌ 远程缺少 {len(only_local)} 个文件（本地有、远程没有）:")
        for p in only_local[:30]:
            print("   -", p)
    if only_remote:
        print(f"❌ 远程多出 {len(only_remote)} 个文件（远程有、本地没有）:")
        for p in only_remote[:30]:
            print("   +", p)
    if diff:
        print(f"❌ 内容不一致 {len(diff)} 个文件:")
        for p in diff[:30]:
            print(f"   ≠ {p}\n       local ={loc[p][1]}\n       remote={rem[p][1]}")

    # 关键文件单独列出，方便人眼确认
    key = ["README.md", "docs/20_官方要求合规自检.md",
           "src/p1_colorbar/rtl/edge_adaptive_96.v",
           "src/p1_colorbar/bitbank/位流台账.md"]
    print("\n关键文件:")
    for p in key:
        st = "OK  " if p in loc and p in rem and loc[p][1] == rem[p][1] else "MISS"
        print(f"  {st} {p}  {rem.get(p, ('', '-', 0))[1][:10]}")

    bits = sorted(p for p in rem if p.endswith(".bit"))
    print(f"\n位流（远程 {len(bits)} 块）:")
    for p in bits:
        print(f"  {rem[p][2]:>10,} B  {rem[p][1][:12]}  {p}")

    if args.deep:
        print("\n深度核对（下载 blob 算 md5）:")
        for p in bits:
            n, md5 = blob_md5(rem[p][1])
            lp = p
            if os.path.exists(lp):
                ln, lmd5 = len(open(lp, "rb").read()), hashlib.md5(open(lp, "rb").read()).hexdigest()
                flag = "OK  " if (n == ln and md5 == lmd5) else "DIFF"
                print(f"  {flag} {os.path.basename(p):<36} 远程 {n:,} B {md5}")
                print(f"       {'':<36} 本地 {ln:,} B {lmd5}")
                ok = ok and flag == "OK  "
            else:
                print(f"  ?    {os.path.basename(p)}  远程 {n:,} B {md5}（本地无此文件）")

    print()
    print("=" * 60)
    print("✅ PASS —— 远程与本地完全一致" if ok else "❌ FAIL —— 存在差异，见上")
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print("核对失败:", e, file=sys.stderr)
        sys.exit(2)
