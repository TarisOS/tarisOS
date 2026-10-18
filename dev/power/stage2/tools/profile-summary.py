#!/usr/bin/python3 -I
# Copyright (C) 2026 George Dobreff ("Witcher") and contributors
# SPDX-License-Identifier: GPL-3.0-only

# Summarises a pw-profiler log (PipeWire 1.6.9's tab format, src/tools/pw-profiler.c dump_point):
# per cycle the period, how long the graph took from the driver's wake-up to its finish, and each
# follower's processing time. Node names come from a pw-dump JSON file.
# Usage: profile-summary.py PROFILER.log PW-DUMP.json

import json, statistics as st, sys

log, dump = sys.argv[1], sys.argv[2]
names = {o["id"]: o.get("info", {}).get("props", {}).get("node.name", "?")
         for o in json.load(open(dump)) if o.get("type") == "PipeWire:Interface:Node"}

periods, graph, over, nodes = [], [], 0, {}
for line in open(log):
    c = line.rstrip("\n").split("\t")
    if len(c) < 4:
        continue
    d1, d2, delay, period = (float(x) for x in c[:4])
    if period <= 0:
        continue
    # dump_point flags a cycle that overran (period or graph time over 1.3 x the period)
    if d1 == d2 == round(period * 1.4, 3) or d2 > period:
        over += 1
    periods.append(period)
    graph.append(d2)
    for i in range(4, len(c) - 7, 8):
        if c[i].strip():
            nodes.setdefault(int(c[i]), []).append(float(c[i + 5]))

def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * p))]

if not graph:
    print("no cycles logged")
    sys.exit(1)
per = st.mean(periods)
print(f"cycles {len(graph)}, period {per / 1000:.2f} ms, overruns {over}")
print(f"graph time (driver wake -> finish): mean {st.mean(graph):.0f} us, "
      f"p99 {pct(graph, .99):.0f} us, "
      f"max {max(graph):.0f} us = {max(graph) / per * 100:.1f} % of the period")
for nid, d in sorted(nodes.items(), key=lambda x: -st.mean(x[1])):
    print(f"  {names.get(nid, '?'):45} mean {st.mean(d):7.1f} us  p99 {pct(d, .99):7.1f}"
          f"  max {max(d):7.1f}")
