#!/usr/bin/python3
"""Load dockrclone jobs, generate cron entries, and run backups."""

import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

import yaml


CONFIG_PATH = Path(os.environ.get("JOBS_FILE", "/config/jobs.yml"))
SNAPSHOT_PATH = Path("/run/dockrclone/jobs.json")
CRON_PATH = Path("/etc/cron.d/dockrclone")
NAME_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")


class ConfigError(Exception):
    pass


def validate_cron_field(value, minimum, maximum, allow_seven=False):
    for item in value.split(","):
        if not item:
            return False
        pieces = item.split("/")
        if len(pieces) > 2:
            return False
        base = pieces[0]
        if len(pieces) == 2:
            if not pieces[1].isdigit() or int(pieces[1]) < 1:
                return False
        if base == "*":
            continue
        bounds = base.split("-")
        if len(bounds) > 2 or not all(part.isdigit() for part in bounds):
            return False
        low = int(bounds[0])
        high = int(bounds[-1])
        allowed_maximum = 7 if allow_seven else maximum
        if low < minimum or high > allowed_maximum or low > high:
            return False
    return True


def validate_schedule(schedule, name):
    if not isinstance(schedule, str):
        raise ConfigError(f"job '{name}': schedule must be a quoted five-field cron expression")
    fields = schedule.split()
    limits = [(0, 59, False), (0, 23, False), (1, 31, False), (1, 12, False), (0, 6, True)]
    if len(fields) != 5:
        raise ConfigError(f"job '{name}': schedule must contain exactly five cron fields")
    for field, (minimum, maximum, allow_seven) in zip(fields, limits):
        if not validate_cron_field(field, minimum, maximum, allow_seven):
            raise ConfigError(f"job '{name}': invalid cron schedule '{schedule}'")
    return " ".join(fields)


def load_jobs(path=CONFIG_PATH, check_sources=True):
    try:
        with open(path, "r", encoding="utf-8") as stream:
            document = yaml.safe_load(stream)
    except FileNotFoundError as exc:
        raise ConfigError(f"jobs file not found: {path}") from exc
    except yaml.YAMLError as exc:
        raise ConfigError(f"invalid YAML in {path}: {exc}") from exc

    if not isinstance(document, dict) or not isinstance(document.get("jobs"), list):
        raise ConfigError("jobs.yml must contain a top-level 'jobs' list")
    if set(document) != {"jobs"}:
        raise ConfigError("jobs.yml only supports the top-level 'jobs' key")
    if not document["jobs"]:
        raise ConfigError("jobs.yml must define at least one job")

    jobs = []
    names = set()
    for index, item in enumerate(document["jobs"], start=1):
        if not isinstance(item, dict):
            raise ConfigError(f"jobs[{index}] must be a mapping")
        unknown = set(item) - {"name", "schedule", "source", "destination", "mode"}
        if unknown:
            raise ConfigError(f"job at jobs[{index}] has unknown field(s): {', '.join(sorted(map(str, unknown)))}")
        name = item.get("name")
        if not isinstance(name, str) or not NAME_PATTERN.fullmatch(name):
            raise ConfigError(f"jobs[{index}].name must use letters, numbers, '_' or '-' and start with a letter or number")
        if name in names:
            raise ConfigError(f"duplicate job name: {name}")
        names.add(name)

        schedule = validate_schedule(item.get("schedule"), name)
        source = item.get("source")
        if not isinstance(source, str) or not source.startswith("/") or any(char in source for char in "\n\r\0"):
            raise ConfigError(f"job '{name}': source must be an absolute container path")
        if check_sources and not os.path.isdir(source):
            raise ConfigError(f"job '{name}': source directory does not exist inside the container: {source}")

        destination = item.get("destination")
        if not isinstance(destination, str) or not destination or any(char in destination for char in "\n\r\0"):
            raise ConfigError(f"job '{name}': destination must be a non-empty rclone path")
        if destination.startswith("-"):
            raise ConfigError(f"job '{name}': destination must not start with '-'")

        mode = item.get("mode")
        if mode not in ("copy", "sync"):
            raise ConfigError(f"job '{name}': mode must be 'copy' or 'sync'")

        jobs.append({
            "name": name,
            "schedule": schedule,
            "source": source,
            "destination": destination,
            "mode": mode,
        })
    return jobs


def atomic_write(path, content, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def prepare():
    jobs = load_jobs()
    snapshot = json.dumps(jobs, ensure_ascii=False, indent=2) + "\n"
    atomic_write(SNAPSHOT_PATH, snapshot, 0o600)

    lines = [
        "SHELL=/bin/sh",
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        f"TZ={os.environ.get('TZ', 'UTC')}",
        f"KUMA_BASE={os.environ.get('KUMA_BASE', '')}",
        f"KUMA_TOKEN={os.environ.get('KUMA_TOKEN', '')}",
        "",
    ]
    for job in jobs:
        lines.append(f"{job['schedule']} root /usr/local/bin/backup.sh {job['name']}")
    atomic_write(CRON_PATH, "\n".join(lines) + "\n", 0o644)
    print(f"jobs: loaded {len(jobs)} job(s) from {CONFIG_PATH}")
    for job in jobs:
        print(f"jobs: {job['name']} schedule='{job['schedule']}' mode={job['mode']}")


def kuma_push(status, message):
    base = os.environ.get("KUMA_BASE", "").rstrip("/")
    token = os.environ.get("KUMA_TOKEN", "")
    if not base and not token:
        return True
    if not base or not token:
        print("backup: KUMA_BASE and KUMA_TOKEN must either both be set or both be empty", file=sys.stderr)
        return False
    query = urllib.parse.urlencode({"status": status, "msg": message})
    request = urllib.request.Request(f"{base}/api/push/{token}?{query}")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return 200 <= response.status < 300
    except Exception as exc:
        print(f"backup: Uptime Kuma push failed: {exc}", file=sys.stderr)
        return False


def run_job(job):
    lock_dir = Path("/run/dockrclone/locks")
    lock_dir.mkdir(parents=True, exist_ok=True)
    lock_path = lock_dir / f"{job['name']}.lock"
    with open(lock_path, "w", encoding="utf-8") as lock_file:
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(f"backup: job '{job['name']}' is already running; skipping")
            return 0

        if not os.path.isdir(job["source"]):
            message = f"job '{job['name']}' source directory is missing: {job['source']}"
            print(f"backup: {message}", file=sys.stderr)
            kuma_push("down", message)
            return 2

        print(f"rclone: starting job={job['name']} source={job['source']} destination={job['destination']} mode={job['mode']}", flush=True)
        result = subprocess.run([
            "rclone",
            job["mode"],
            "--config=/config/rclone.conf",
            "--stats=30s",
            job["source"].rstrip("/") + "/",
            job["destination"],
        ], check=False)
        if result.returncode:
            message = f"job '{job['name']}' failed with exit code {result.returncode}"
            print(f"rclone: {message}", file=sys.stderr)
            kuma_push("down", message)
            return result.returncode

        print(f"rclone: job '{job['name']}' completed successfully")
        if not kuma_push("up", f"{job['name']} completed"):
            return 1
        return 0


def run(job_name=None):
    try:
        with open(SNAPSHOT_PATH, "r", encoding="utf-8") as stream:
            jobs = json.load(stream)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"backup: cannot read active job configuration: {exc}", file=sys.stderr)
        return 2

    if job_name is not None:
        selected = [job for job in jobs if job["name"] == job_name]
        if not selected:
            print(f"backup: unknown job '{job_name}'", file=sys.stderr)
            return 2
    else:
        selected = jobs

    status = 0
    for job in selected:
        result = run_job(job)
        if result:
            status = result
    return status


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if command == "validate":
            jobs = load_jobs(check_sources=True)
            print(f"jobs: {len(jobs)} job(s) valid")
            return 0
        if command == "prepare":
            prepare()
            return 0
        if command == "run":
            if len(sys.argv) > 3:
                print("usage: backup.sh [job-name]", file=sys.stderr)
                return 2
            return run(sys.argv[2] if len(sys.argv) == 3 else None)
        print("usage: jobs.py {validate|prepare|run [job-name]}", file=sys.stderr)
        return 2
    except ConfigError as exc:
        print(f"jobs: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
