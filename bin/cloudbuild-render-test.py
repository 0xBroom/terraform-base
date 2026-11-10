#!/usr/bin/env python3
"""Deterministic self-test for bin/cloudbuild-render.py and the shared pipeline.

Run it: `python3 bin/cloudbuild-render-test.py`. Exit 0 is the only pass.

It builds a throw-away workspace against the REAL cloudbuild_files/cloudbuild.yaml, so
a step whose x-when flag stops matching a capability, or a waitFor pointing at a step
that no longer exists, fails here rather than in a build. Every check has a positive
control: a filter that removes everything proves nothing.
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import sys
import tempfile

BIN = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(BIN)

sys.dont_write_bytecode = True  # a test does not leave __pycache__ in the repository
spec = importlib.util.spec_from_file_location("cbrender", os.path.join(BIN, "cloudbuild-render.py"))
cb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cb)

DEFAULTS = """
region_name: europe-west1
client:
  name: "tt"
"""

WORKSPACE = """
project:
  id: "test-project"
  number: "1"
repo_providers:
  default: "github"
app:
  service:
    plain:
      name: "plain"
      cloudbuild:
        repo_name: "plain-repo"
        inline: true
        branch_pattern: "^main$"
    quoted:
      name: "quoted"
      cloudbuild:
        repo_name: "quoted-repo"
        inline: true
        docker_target: "api"
        artifact_registry_token: true
        build_timeout: "2400s"
        machine_type: "E2_HIGHCPU_8"
        build_args:
          B_SPACES: "two words"
          A_QUOTE: "it's here"
          C_DOLLAR: "$HOME and ${_NOT_EXPANDED}"
          D_EMPTY: ""
    companion:
      name: "companion"
      cloudbuild:
        repo_name: "companion-repo"
        inline: true
        job_name: "tt-companion-tasks"
    nodeploy:
      name: "nodeploy"
      cloudbuild:
        repo_name: "base-repo"
        inline: true
        deploy: false
    faraway:
      name: "faraway"
      cloudbuild:
        repo_name: "faraway-repo"
        inline: true
      cloudrun:
        region: "us-east1"
    external:
      name: "external"
      cloudbuild:
        repo_name: "ext-repo"
        inline: false
        cloudbuild_file_path: "ci/cloudbuild.yaml"
        substitutions:
          _WHATEVER: "passed through"
  job:
    lonely:
      name: "lonely"
      cloudbuild:
        repo_name: "job-repo"
        inline: true
      job-config:
        image: "tt-house-jobs/lonely:latest"
"""

failures = []


def check(label, got, want):
    if got != want:
        failures.append(f"{label}\n     got:  {got!r}\n     want: {want!r}")


def step_ids(result):
    return [s.get("id") for s in result["steps"]]


def main() -> int:
    root = tempfile.mkdtemp(prefix="cbrender-test-")
    try:
        os.makedirs(os.path.join(root, "settings"))
        os.makedirs(os.path.join(root, "cloudbuild_files"))
        with open(os.path.join(root, "settings", "default.yaml"), "w") as fh:
            fh.write(DEFAULTS)
        with open(os.path.join(root, "settings", "tw.yaml"), "w") as fh:
            fh.write(WORKSPACE)
        shutil.copy(
            os.path.join(ROOT, "cloudbuild_files", "cloudbuild.yaml"),
            os.path.join(root, "cloudbuild_files", "cloudbuild.yaml"),
        )

        settings = cb.load_settings(root, "tw")
        configs = cb.collect_configs(settings, "tw")
        rendered = {k: cb.render(v, settings, "tw", root) for k, v in configs.items() if v["inline"]}

        # 1. The capability filter, in both directions.
        check("plain service: no token step, no job step",
              step_ids(rendered["plain"]), ["build", "push", "deploy-service"])
        check("token capability adds its step back",
              step_ids(rendered["quoted"]), ["ar-token", "build", "push", "deploy-service"])
        check("a service with a companion job updates it too",
              step_ids(rendered["companion"]), ["build", "push", "deploy-service", "update-companion-job"])
        check("deploy: false builds and pushes only",
              step_ids(rendered["nodeploy"]), ["build", "push"])
        check("a job updates the job, and never deploys a service",
              step_ids(rendered["lonely"]), ["build", "push", "deploy-job"])

        # 2. waitFor is rewritten for the steps that survive.
        check("build waits for nothing once ar-token is filtered out",
              rendered["plain"]["steps"][0]["waitFor"], None)
        check("build still waits for ar-token when it is there",
              rendered["quoted"]["steps"][1]["waitFor"], ["ar-token"])
        check("push always waits for build",
              rendered["plain"]["steps"][1]["waitFor"], ["build"])
        for key, result in rendered.items():
            ids = set(step_ids(result))
            for step in result["steps"]:
                for w in step.get("waitFor") or []:
                    if w != "-" and w not in ids:
                        failures.append(f"{key}: step {step.get('id')} waits for '{w}', which is not in the build")

        # 3. Build args: sorted, quoted, and nothing the shell can reinterpret.
        check("build args are sorted and POSIX-quoted",
              cb.render_build_args(configs["quoted"]),
              '--build-arg GOOGLE_ACCESS_TOKEN="$(cat /workspace/access_token.txt)" '
              "--build-arg A_QUOTE='it'\\''s here' "
              "--build-arg B_SPACES='two words' "
              "--build-arg C_DOLLAR='$HOME and ${_NOT_EXPANDED}' "
              "--build-arg D_EMPTY=''")
        check("no build args means no build args", cb.render_build_args(configs["plain"]), "")
        check("a base image is a build argument like any other",
              cb.render_build_args({**configs["plain"], "image_base": "base/img:1"}),
              "--build-arg IMAGE_BASE='base/img:1'")

        # 4. Substitutions: computed, complete, and no leftovers.
        subs = cb.substitutions(configs["companion"], settings, "tw")
        check("the job to update is named", subs.get("_JOB_NAME"), "tt-companion-tasks")
        check("the image is fully resolved at plan time",
              subs["_IMAGE"], "europe-west1-docker.pkg.dev/test-project/tt-companion/companion")
        check("a job image comes from job-config, without its tag",
              cb.substitutions(configs["lonely"], settings, "tw")["_IMAGE"],
              "europe-west1-docker.pkg.dev/test-project/tt-house-jobs/lonely")
        check("a multi-stage target is a docker flag, not a build arg",
              cb.substitutions(configs["quoted"], settings, "tw")["_DOCKER_TARGET"], "--target=api")
        check("no target means the flag disappears entirely", subs["_DOCKER_TARGET"], "")
        check("an inline build carries no dead substitutions",
              sorted(subs), ["_BUILD_ARGS", "_BUILD_CONTEXT_PATH", "_DEPLOY_REGION", "_DOCKERFILE_PATH",
                             "_DOCKER_TARGET", "_ENV", "_GCP_REGION", "_IMAGE", "_JOB_NAME", "_JOB_REGION",
                             "_PREFIXED_NAME", "_RAW_NAME"])

        # The rollout goes where the resource is, not where the project is. Deploying a
        # us-east1 service to the project region creates a second service.
        check("a service outside the project region deploys to its own",
              cb.substitutions(configs["faraway"], settings, "tw")["_DEPLOY_REGION"], "us-east1")
        check("everything else deploys to the project region", subs["_DEPLOY_REGION"], "europe-west1")
        check("a job is always in the project region",
              cb.substitutions(configs["lonely"], settings, "tw")["_JOB_REGION"], "europe-west1")
        check("a build that deploys nothing names no region",
              "_DEPLOY_REGION" in cb.substitutions(configs["nodeploy"], settings, "tw"), False)
        ext = cb.substitutions(configs["external"], settings, "tw")
        check("a pipeline we cannot read keeps its passthrough substitution",
              ext.get("_WHATEVER"), "passed through")
        check("...and still gets the registry helpers", "_PYTHON_REPO_URL" in ext, True)
        check("...but never the shared pipeline's own substitutions, which it may read "
              "as a signal that they are unset",
              sorted(k for k in ext if k in ("_IMAGE", "_BUILD_ARGS", "_DOCKER_TARGET", "_JOB_NAME")), [])

        # 5. Overrides from settings win over the pipeline's defaults.
        check("timeout override", rendered["quoted"]["timeout"], "2400s")
        check("timeout default", rendered["plain"]["timeout"], "1800s")
        check("machine type override", rendered["quoted"]["machine_type"], "E2_HIGHCPU_8")

        # 6. Substitution of the step text is what Cloud Build does, no more.
        text = cb.apply_substitutions("${_IMAGE}:${SHORT_SHA} $_ENV ${_MISSING}x", {"_IMAGE": "img", "_ENV": "tw"})
        check("builtins are left for Cloud Build, unknown custom ones vanish",
              text, "img:${SHORT_SHA} tw x")

        # 7. A typo in x-when is an error, not a step that quietly stops running.
        try:
            cb.filter_steps({"steps": [{"id": "s", "x-when": ["no_such_flag"]}]}, {"deploy_service": True})
            failures.append("an unknown x-when flag was accepted")
        except KeyError:
            pass

        # 8. Every capability the pipeline mentions is one Terraform computes.
        import yaml
        with open(os.path.join(ROOT, "cloudbuild_files", "cloudbuild.yaml")) as fh:
            pipeline = yaml.safe_load(fh)
        used = {f for s in pipeline["steps"] for f in s.get("x-when", [])}
        known = set(configs["plain"]["capabilities"])
        check("the pipeline uses only known capabilities", sorted(used - known), [])
        check("every capability is exercised by some step", sorted(known - used), [])

    finally:
        shutil.rmtree(root, ignore_errors=True)

    if failures:
        print(f"FAIL: {len(failures)} check(s):")
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    print("PASS: cloudbuild renderer and pipeline agree on every check")
    return 0


if __name__ == "__main__":
    sys.exit(main())
