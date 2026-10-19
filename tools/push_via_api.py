#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
github.com:443 被网络挡住时的上传旁路：用 GitHub Git Data API 写真实提交。

适用场景
--------
`git push` 报 `CONNECT tunnel failed, response 502`，但 `api.github.com` 正常。
（先跑 tools/verify_remote.py 看差异，再跑本脚本上传，上传后**再核对一次**。）

做的事
------
1. 读远程 base 分支的树 + 本地 HEAD 的树，**自动算差异**（不用手写文件清单）；
2. 差异文件逐个上传为 blob（删除的文件用 sha=None 标记）；
3. 在 base 树上打补丁 → 建提交 → 移动 ref；
4. 以两父建 merge commit 给 main。

不是伪造：commit 的 tree 与本地 HEAD 完全一致，parent 指向远程当前 HEAD。

用法
----
    # token：从本机凭据库取（不落盘、不打印）
    export GH_TOKEN=$(printf 'protocol=https\\nhost=github.com\\n\\n' \\
        | git -c credential.helper= -c credential.helper=manager credential fill \\
        | sed -n 's/^password=//p')

    python tools/push_via_api.py                 # 用本地 HEAD 的提交信息
    python tools/push_via_api.py -m "说明"       # 自定义提交信息
"""

import argparse
import base64
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


def gh(method, path, payload=None):
    url = path if path.startswith("http") else API + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {os.environ['GH_TOKEN']}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "push-via-api")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=180, context=CTX) as r:
            body = r.read().decode()
            return json.loads(body) if body.strip() else {}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path} -> {e.code}: {e.read().decode()[:400]}") from None


def remote_blobs(branch):
    head = gh("GET", f"/git/ref/heads/{branch}")["object"]["sha"]
    tree = gh("GET", f"/git/trees/{head}?recursive=1")["tree"]
    return head, {e["path"]: e["sha"] for e in tree if e["type"] == "blob"}


def local_blobs(rev="HEAD"):
    out = subprocess.run(["git", "ls-tree", "-r", "-z", rev],
                         capture_output=True, check=True).stdout
    res = {}
    for rec in out.split(b"\0"):
        if not rec:
            continue
        meta, path = rec.split(b"\t", 1)
        _mode, _typ, sha = meta.decode().split()
        res[path.decode("utf-8", "surrogateescape")] = sha
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-branch", default="b4-osd")
    ap.add_argument("--main-branch", default="main")
    ap.add_argument("-m", "--message", default=None)
    args = ap.parse_args()

    if not os.environ.get("GH_TOKEN"):
        print("缺 GH_TOKEN 环境变量（见文件头注释里的取法）", file=sys.stderr)
        return 1

    base_sha, rem = remote_blobs(args.base_branch)
    loc = local_blobs()
    short = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                           capture_output=True, text=True).stdout.strip()
    print(f"远程 {args.base_branch} = {base_sha[:10]}  文件 {len(rem)}")
    print(f"本地 HEAD = {short}  文件 {len(loc)}")

    changed = sorted(p for p in loc if rem.get(p) != loc[p])
    deleted = sorted(p for p in rem if p not in loc)
    if not changed and not deleted:
        print("没有差异，不需要上传。")
        return 0
    print(f"需上传 {len(changed)} 个，删除 {len(deleted)} 个")

    entries = []
    for p in changed:
        raw = open(p, "rb").read()
        sha = gh("POST", "/git/blobs",
                 {"content": base64.b64encode(raw).decode(), "encoding": "base64"})["sha"]
        entries.append({"path": p, "mode": "100644", "type": "blob", "sha": sha})
        print(f"  + {len(raw):>9,} B  {sha[:10]}  {p}")
    for p in deleted:
        entries.append({"path": p, "mode": "100644", "type": "blob", "sha": None})
        print(f"  - 删除 {p}")

    msg = args.message or subprocess.run(
        ["git", "log", "-1", "--format=%B"], capture_output=True, text=True
    ).stdout.strip()

    base_tree = gh("GET", f"/git/commits/{base_sha}")["tree"]["sha"]
    new_tree = gh("POST", "/git/trees", {"base_tree": base_tree, "tree": entries})["sha"]
    c1 = gh("POST", "/git/commits",
            {"message": msg, "tree": new_tree, "parents": [base_sha]})["sha"]
    gh("PATCH", f"/git/refs/heads/{args.base_branch}", {"sha": c1, "force": True})
    print(f"{args.base_branch} -> {c1[:10]}")

    if args.main_branch:
        main_sha = gh("GET", f"/git/ref/heads/{args.main_branch}")["object"]["sha"]
        c2 = gh("POST", "/git/commits",
                {"message": f"Merge branch '{args.base_branch}'", "tree": new_tree,
                 "parents": [main_sha, c1]})["sha"]
        gh("PATCH", f"/git/refs/heads/{args.main_branch}", {"sha": c2, "force": True})
        print(f"{args.main_branch} -> {c2[:10]}（merge）")

    print(f"\n完成。下一步必须核对：python tools/verify_remote.py --branch {args.main_branch} --deep")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print("FAILED:", e, file=sys.stderr)
        sys.exit(1)
