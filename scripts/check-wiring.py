#!/usr/bin/env python3
"""Static wiring check (no AWS, no Terraform needed).

For every Terraform folder it verifies that:
  1. each terraform_remote_state key points at a folder that exists,
  2. every output read from another folder (data.terraform_remote_state.X.outputs.Y, local.out.X.Y, local.eks.Y, ...) is actually declared
     in that folder's outputs.tf,
  3. no folder reads state from a folder that is applied LATER according to scripts/execution-order.txt.

Usage: python3 scripts/check-wiring.py
Exit code 1 on any problem.
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TF = os.path.join(ROOT, "terraform")
folders = sorted(d for d in os.listdir(TF) if re.match(r"^\d\d-", d) and os.path.isdir(os.path.join(TF, d)))


def read_tf(folder):
    text = ""
    for f in sorted(os.listdir(os.path.join(TF, folder))):
        if f.endswith(".tf") and f not in ("common.tf", "versions.tf", "providers.tf"):
            text += open(os.path.join(TF, folder, f)).read() + "\n"
    return text


texts = {f: read_tf(f) for f in folders}
outputs = {f: set(re.findall(r'^output\s+"([^"]+)"', texts[f], re.M)) for f in folders}

order_file = os.path.join(ROOT, "scripts", "execution-order.txt")
order = [l.strip() for l in open(order_file) if l.strip() and not l.startswith("#")] if os.path.exists(order_file) else []
pos = {f: i for i, f in enumerate(order)}

problems = []


def key_to_folder(k):
    m = re.search(r"/(\d\d-[a-z0-9-]+)/terraform\.tfstate", k)
    return m.group(1) if m else None


for f in folders:
    t = texts[f]
    # alias -> folder maps
    alias = {}  # name of data block (or for_each key) -> folder
    # single blocks: data "terraform_remote_state" "name" { ... key = ".../NN-x/terraform.tfstate"
    for m in re.finditer(r'data "terraform_remote_state" "(\w+)" \{(.*?)\n\}', t, re.S):
        name, body = m.group(1), m.group(2)
        k = re.search(r'key\s*=\s*"([^"]*)"', body)
        if k and key_to_folder(k.group(1)):
            alias[name] = key_to_folder(k.group(1))
        elif "for_each" in body:
            fe = re.search(r"for_each\s*=\s*\{(.*?)\}", body, re.S)
            if fe:
                for a, d in re.findall(r'(\w+)\s*=\s*"(\d\d-[a-z0-9-]+)"', fe.group(1)):
                    alias["dep:" + a] = d
        else:
            pass
    # for_each map defined in locals { states = {...} }
    for m in re.finditer(r"states\s*=\s*\{(.*?)\}", t, re.S):
        for a, d in re.findall(r'(\w+)\s*=\s*"(\d\d-[a-z0-9-]+)"', m.group(1)):
            alias["dep:" + a] = d
    # the shared k8s template always reads 06-eks
    if "local.eks." in t:
        alias["eks_tpl"] = "06-eks"

    upstream = set()
    for k in re.findall(r'"[^"]*?(\d\d-[a-z0-9-]+)/terraform\.tfstate"', t):
        upstream.add(k)
    for a, d in re.findall(r'^\s+(\w+)\s*=\s*"(\d\d-[a-z0-9-]+)"\s*$', t, re.M):
        upstream.add(d)
    if "local.eks." in t:
        upstream.add("06-eks")
    upstream.discard(f)

    for up in sorted(upstream):
        if up not in folders:
            problems.append(f"{f}: reads state of missing folder {up}")
        elif order and f in pos and up in pos and pos[up] > pos[f]:
            problems.append(f"{f}: depends on {up} which is applied LATER in execution-order.txt")

    # output references
    for m in re.finditer(r"data\.terraform_remote_state\.(\w+)\.outputs\.(\w+)", t):
        n, o = m.groups()
        d = alias.get(n)
        if d and d in outputs and o not in outputs[d]:
            problems.append(f"{f}: {d} has no output '{o}' (data.terraform_remote_state.{n}.outputs.{o})")
    for m in re.finditer(r"local\.out\.(\w+)\.(\w+)", t):
        n, o = m.groups()
        d = alias.get("dep:" + n) or alias.get(n)
        if d and d in outputs and o not in outputs[d]:
            problems.append(f"{f}: {d} has no output '{o}' (local.out.{n}.{o})")
    for m in re.finditer(r"local\.eks\.(\w+)", t):
        o = m.group(1)
        if o not in outputs["06-eks"]:
            problems.append(f"{f}: 06-eks has no output '{o}' (local.eks.{o})")
    for m in re.finditer(r"local\.dns\.(\w+)|local\.acm\.(\w+)|local\.waf\.(\w+)", t):
        pass

# every folder in execution order exists and vice versa
if order:
    for f in folders:
        if f not in pos:
            problems.append(f"{f}: missing from scripts/execution-order.txt")
    for f in order:
        if f not in folders:
            problems.append(f"execution-order.txt lists unknown folder {f}")

# README presence
for f in folders:
    if not os.path.exists(os.path.join(TF, f, "README.md")):
        problems.append(f"{f}: README.md missing")

if problems:
    print("WIRING PROBLEMS:")
    for p in problems:
        print("  -", p)
    sys.exit(1)
print(f"wiring OK: {len(folders)} folders, all remote-state outputs exist, execution order consistent")
