#!/usr/bin/env python3
"""Would an Artifact Registry cleanup policy delete an image something is running?

Artifact Registry cleanup policies know nothing about Cloud Run. A "keep the 2 most
recent" policy deletes the image a job pins by an old tag just as happily as a stale
build. This script answers the question before Google does:

  1. lists every repository in the given projects, and every image version in each;
  2. lists every image in use: the revision behind each Cloud Run service's traffic
     (and tagged revisions), each service's template, and each Cloud Run job;
  3. evaluates the cleanup policy the way Artifact Registry does (a version goes when a
     DELETE policy matches it and no KEEP policy does) and reports what it would
     delete, and whether any of it is in use.

Policy source:
  default         the policy each repository has NOW (dry-run counts as deleting nothing)
  --policy FILE   one cleanupPolicies object (API JSON shape) applied to every repo:
                  a simulation, for deciding a policy before terraform writes it.

Exit 0: nothing in use would be deleted. Exit 1: something in use would be. Exit 2:
could not read what it needed. Read-only; it never deletes anything.

  python3 bin/ar-cleanup-check.py --project my-project --project my-other-project
  python3 bin/ar-cleanup-check.py --project my-project --policy /tmp/p.json --cache /tmp/c
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys

NOW = dt.datetime.now(dt.timezone.utc)


def gcloud(args: list[str], cache: str | None, key: str):
    if cache:
        path = os.path.join(cache, re.sub(r"[^A-Za-z0-9_.-]", "_", key) + ".json")
        if os.path.exists(path):
            with open(path) as f:
                return json.load(f)
    r = subprocess.run(["gcloud", *args, "--format=json"], capture_output=True, text=True)
    if r.returncode != 0:
        err = r.stderr.strip().splitlines()
        return {"_error": err[-1] if err else f"exit {r.returncode}"}
    data = json.loads(r.stdout or "[]")
    if cache:
        os.makedirs(cache, exist_ok=True)
        with open(path, "w") as f:
            json.dump(data, f)
    return data


def ts(s: str) -> dt.datetime:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def seconds(d: str | None) -> float | None:
    return float(d.rstrip("s")) if d else None


def in_use(project: str, cache: str | None) -> set[str]:
    """Every image reference something runs, as 'host/path/pkg@sha256:..' or ':tag'."""
    refs: set[str] = set()
    svcs = gcloud(["run", "services", "list", f"--project={project}"], cache, f"svc-{project}")
    if isinstance(svcs, dict):
        sys.exit(f"ERROR {project}: cannot list services: {svcs['_error']}")
    revs_needed = set()
    for s in svcs:
        region = s["metadata"]["labels"]["cloud.googleapis.com/location"]
        refs.add(s["spec"]["template"]["spec"]["containers"][0]["image"])
        for t in s.get("status", {}).get("traffic", []):
            if t.get("percent", 0) > 0 or t.get("tag"):
                revs_needed.add((region, t["revisionName"]))
        if s.get("status", {}).get("latestReadyRevisionName"):
            revs_needed.add((region, s["status"]["latestReadyRevisionName"]))
    for region, rev in sorted(revs_needed):
        r = gcloud(["run", "revisions", "describe", rev, f"--project={project}", f"--region={region}"],
                   cache, f"rev-{project}-{rev}")
        if isinstance(r, dict) and "_error" in r:
            sys.exit(f"ERROR {project}: cannot read revision {rev}: {r['_error']}")
        refs.add(r["spec"]["containers"][0]["image"])
        if r.get("status", {}).get("imageDigest"):
            refs.add(r["status"]["imageDigest"])
    jobs = gcloud(["run", "jobs", "list", f"--project={project}"], cache, f"jobs-{project}")
    if isinstance(jobs, dict):
        sys.exit(f"ERROR {project}: cannot list jobs: {jobs['_error']}")
    for j in jobs:
        refs.add(j["spec"]["template"]["spec"]["template"]["spec"]["containers"][0]["image"])
    # A bare image name is Docker's implicit ":latest".
    return {r if "@" in r or ":" in r.rsplit("/", 1)[-1] else f"{r}:latest" for r in refs}


def matches_condition(v: dict, c: dict) -> bool:
    state = c.get("tagState", "ANY")
    if state == "TAGGED" and not v["tags"]:
        return False
    if state == "UNTAGGED" and v["tags"]:
        return False
    if c.get("tagPrefixes") and not any(t.startswith(p) for t in v["tags"] for p in c["tagPrefixes"]):
        return False
    if c.get("packageNamePrefixes") and not any(v["package"].startswith(p) for p in c["packageNamePrefixes"]):
        return False
    if c.get("versionNamePrefixes") and not any(v["digest"].startswith(p) for p in c["versionNamePrefixes"]):
        return False
    age = (NOW - v["created"]).total_seconds()
    if c.get("olderThan") is not None and age < seconds(c["olderThan"]):
        return False
    if c.get("newerThan") is not None and age > seconds(c["newerThan"]):
        return False
    return True


def evaluate(versions: list[dict], policies: dict) -> list[dict]:
    """Return the versions the policy would delete."""
    keep = set()
    for p in policies.values():
        if p.get("action") != "KEEP":
            continue
        if "mostRecentVersions" in p:
            m = p["mostRecentVersions"]
            pre = m.get("packageNamePrefixes")
            by_pkg: dict[str, list[dict]] = {}
            for v in versions:
                if not pre or any(v["package"].startswith(x) for x in pre):
                    by_pkg.setdefault(v["package"], []).append(v)
            for vs in by_pkg.values():
                vs.sort(key=lambda v: v["created"], reverse=True)
                keep.update(id(v) for v in vs[: int(m.get("keepCount", 0))])
        if "condition" in p:
            keep.update(id(v) for v in versions if matches_condition(v, p["condition"]))
    gone = []
    for v in versions:
        if id(v) in keep:
            continue
        if any(p.get("action") == "DELETE" and matches_condition(v, p.get("condition", {}))
               for p in policies.values()):
            gone.append(v)
    return gone


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", action="append", required=True)
    ap.add_argument("--policy", help="simulate this cleanupPolicies JSON on every repository")
    ap.add_argument("--cache", help="directory to cache gcloud reads (re-runs are instant)")
    ap.add_argument("--quiet", action="store_true", help="print only the verdict and problems")
    a = ap.parse_args()
    sim = None
    if a.policy:
        with open(a.policy) as f:
            sim = json.load(f)

    bad, total_now, total_gone, unread = [], 0, 0, []
    for project in a.project:
        refs = in_use(project, a.cache)
        repos = gcloud(["artifacts", "repositories", "list", f"--project={project}"], a.cache, f"repos-{project}")
        if isinstance(repos, dict):
            sys.exit(f"ERROR {project}: cannot list repositories: {repos['_error']}")
        for repo in repos:
            _, _, _, loc, _, name = repo["name"].split("/")
            if repo.get("format") != "DOCKER":
                continue
            full = gcloud(["artifacts", "repositories", "describe", name, f"--location={loc}", f"--project={project}"],
                          a.cache, f"desc-{project}-{loc}-{name}")
            host = f"{loc}-docker.pkg.dev/{project}/{name}"
            imgs = gcloud(["artifacts", "docker", "images", "list", host, "--include-tags"], a.cache, f"img-{project}-{loc}-{name}")
            if isinstance(imgs, dict):
                unread.append(f"{host}: {imgs['_error']}")
                continue
            versions = [{
                "package": i["package"].rsplit("/", 1)[-1],
                "path": i["package"],
                "digest": i["version"],
                "tags": [t for t in (i.get("tags") or []) if t] if isinstance(i.get("tags"), list)
                        else [t for t in (i.get("tags") or "").split(",") if t],
                "created": ts(i["createTime"]),
                "bytes": int(str(i.get("metadata", {}).get("imageSizeBytes") or 0).replace("None", "0")),  # gcloud prints a literal "None"
            } for i in imgs]
            # A reference into this repository that names no version is already broken: the
            # check that matters AFTER a cleanup has run, when there is nothing left to simulate.
            present = set()
            for v in versions:
                present |= {f"{v['path']}@{v['digest']}"} | {f"{v['path']}:{t}" for t in v["tags"]}
            for ref in refs:
                if ref.startswith(host + "/") and ref not in present:
                    bad.append(f"{ref} is IN USE and MISSING from the repository")
            if sim is not None:
                policies = sim
            elif full.get("cleanupPolicyDryRun"):
                policies = {}
            else:
                policies = full.get("cleanupPolicies", {})
            gone = evaluate(versions, policies)
            size_now = sum(v["bytes"] for v in versions)
            size_gone = sum(v["bytes"] for v in gone)
            total_now += size_now
            total_gone += size_gone
            for v in gone:
                names = {f"{v['path']}@{v['digest']}", v["digest"]} | {f"{v['path']}:{t}" for t in v["tags"]}
                hit = names & refs
                if hit:
                    bad.append(f"{host}/{v['package']} {v['digest'][:19]} tags={v['tags']} is IN USE ({sorted(hit)[0]})")
            if not a.quiet:
                print(f"{host:<75} {len(versions):>4} versions {size_now/1e9:7.2f} GB  -> deletes {len(gone):>4} ({size_gone/1e9:6.2f} GB)")

    print(f"\nimage bytes (shared layers counted per image): {total_now/1e9:.2f} GB, policy deletes {total_gone/1e9:.2f} GB")
    for u in unread:
        print(f"UNREAD {u}")
    for b in bad:
        print(f"FAIL {b}")
    if bad:
        print(f"FAIL: {len(bad)} image reference(s) in use are missing or would be deleted")
        return 1
    if unread:
        return 2
    print("PASS: no image in use would be deleted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
