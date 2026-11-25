#!/usr/bin/env python3
"""Git context for the decision log, read from .git files and never from git.

A hook that records a permission prompt has a few milliseconds to spare, and
must not run a program that can itself be configured (hooks, fsmonitor,
credential helpers). So this module reads the files: HEAD, the loose ref or
packed-refs, config, refs/remotes/origin/HEAD and FETCH_HEAD, following a
linked worktree's .git file to its gitdir and commondir. Dirty state and
ahead/behind counts need the index and are not captured.

  find_repo(path)       the Repo containing path, or None
  Repo.info()           branch, head_sha, repo_key, remote_url, default_branch,
                        upstream, upstream_sha, fetched_at, branch_class, worktree
  Repo.ref_sha(ref)     the sha of refs/heads/x, refs/remotes/origin/x, ...
  normalise_remote(u)   (repo_key, url without userinfo) for an origin URL
  branch_class(...)     default | protected | feature | detached
  track_dirs(...)       the directory (and branch) each command segment runs in

python3 -I gitctx.py --self-test builds throwaway repositories with git (the
tests may run git, the library never does) and checks a main checkout, a
linked worktree, a detached HEAD, a branch that exists only in packed-refs,
and no remote.
"""

import os
import re
import sys

SHA = re.compile(r"^[0-9a-f]{40}([0-9a-f]{24})?$")
PROTECTED = re.compile(r"^(main|master|release/.*|prod.*|production|hotfix/.*)$")
SECTION = re.compile(r'^\s*\[\s*([A-Za-z0-9.-]+)(?:\s+"((?:[^"\\]|\\.)*)")?\s*\]\s*(.*)$')
KEYVAL = re.compile(r"^\s*([A-Za-z][A-Za-z0-9-]*)\s*(?:=\s*(.*?))?\s*$")
BACKTICK = chr(96)


def _read(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def parse_config(text):
    """Return {(section, subsection): {key: value}}, section and key lowercased.

    Includes are not followed, so a value set through include.path is missed."""
    out, cur = {}, None
    for line in (text or "").splitlines():
        m = SECTION.match(line)
        if m:
            name, sub, rest = m.group(1).lower(), m.group(2), m.group(3)
            if sub is None and "." in name:
                name, sub = name.split(".", 1)
            cur = out.setdefault((name, sub), {})
            line = rest
        if cur is None or line.lstrip().startswith(("#", ";")):
            continue
        m = KEYVAL.match(line)
        if not m:
            continue
        value = m.group(2)
        if value is None:
            value = "true"
        elif value.startswith('"') and value.count('"') >= 2:
            value = value[1:value.rindex('"')]
        else:
            value = re.split(r"\s[#;]", value, maxsplit=1)[0].strip()
        cur[m.group(1).lower()] = value
    return out


def normalise_remote(url):
    """Return (repo_key, url without userinfo), or (None, url) for a local path."""
    if not url:
        return None, url
    url = url.strip()
    m = re.match(r"^([A-Za-z][A-Za-z0-9+.-]*)://(?:[^/@]*@)?([^/:]+)(?::\d+)?/(.+)$", url)
    if m:
        scheme, host, path = m.groups()
        clean = f"{scheme}://{host}/{path}"
        if scheme == "file":
            return None, clean
    else:
        m = re.match(r"^(?:[^/@]+@)?([A-Za-z0-9.-]+):(?!//)(.+)$", url)
        if not m or url.startswith(("/", ".", "~")):
            return None, url
        host, path = m.groups()
        clean = f"{host}:{path}"
    path = re.sub(r"(\.git)?/*$", "", path.lstrip("/"))
    return (f"{host.lower()}/{path}" if path else None), clean


def branch_class(branch, default_branch=None, detached=False):
    if detached or not branch:
        return "detached"
    if default_branch:
        if branch == default_branch:
            return "default"
    elif branch in ("main", "master"):
        return "default"
    return "protected" if PROTECTED.match(branch) else "feature"


class Repo:
    def __init__(self, toplevel, gitdir, commondir):
        self.toplevel, self.gitdir, self.commondir = toplevel, gitdir, commondir
        self.linked = os.path.realpath(gitdir) != os.path.realpath(commondir)
        self._config = None

    def config(self):
        if self._config is None:
            self._config = parse_config(_read(os.path.join(self.commondir, "config")))
        return self._config

    def config_value(self, section, sub, key):
        return self.config().get((section, sub), {}).get(key)

    def head(self):
        """Return (branch, sha): branch is None when HEAD is detached."""
        text = (_read(os.path.join(self.gitdir, "HEAD")) or "").strip()
        if text.startswith("ref:"):
            ref = text[4:].strip()
            branch = ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref
            return branch, self.ref_sha(ref)
        return None, (text if SHA.match(text) else None)

    def ref_sha(self, ref, depth=0):
        if depth > 5 or ".." in ref:
            return None
        for base in (self.commondir, self.gitdir):
            text = (_read(os.path.join(base, ref)) or "").strip()
            if text.startswith("ref:"):
                return self.ref_sha(text[4:].strip(), depth + 1)
            if SHA.match(text):
                return text
        for line in (_read(os.path.join(self.commondir, "packed-refs")) or "").splitlines():
            if line[:1] in ("#", "^"):
                continue
            sha, _, name = line.partition(" ")
            if name == ref and SHA.match(sha):
                return sha
        return None

    def default_branch(self, remote="origin"):
        """The branch refs/remotes/<remote>/HEAD points at, from the loose file only."""
        text = (_read(os.path.join(self.commondir, "refs", "remotes", remote, "HEAD")) or "").strip()
        prefix = f"ref: refs/remotes/{remote}/"
        return text[len(prefix):] if text.startswith(prefix) else None

    def fetched_at(self):
        try:
            return int(os.stat(os.path.join(self.commondir, "FETCH_HEAD")).st_mtime * 1000)
        except OSError:
            return None

    def main_path(self):
        if os.path.basename(self.commondir) == ".git":
            return os.path.dirname(self.commondir)
        return self.commondir

    def info(self):
        branch, sha = self.head()
        url = self.config_value("remote", "origin", "url")
        key, clean = normalise_remote(url)
        default = self.default_branch()
        upstream = upstream_sha = None
        if branch:
            remote = self.config_value("branch", branch, "remote")
            merge = self.config_value("branch", branch, "merge") or ""
            if remote and remote != "." and merge.startswith("refs/heads/"):
                name = merge[len("refs/heads/"):]
                upstream = f"{remote}/{name}"
                upstream_sha = self.ref_sha(f"refs/remotes/{remote}/{name}")
        return {
            "toplevel": self.toplevel,
            "repo_key": key or "path:" + self.commondir,
            "remote_url": clean if url else None,
            "main_path": self.main_path(),
            "default_branch": default,
            "worktree": self.toplevel if self.linked else None,
            "branch": branch,
            "head_sha": sha,
            "upstream": upstream,
            "upstream_sha": upstream_sha,
            "fetched_at": self.fetched_at(),
            "branch_class": branch_class(branch, default, detached=branch is None),
            "push_default": self.config_value("push", None, "default"),
        }


def find_repo(path):
    p = os.path.abspath(os.path.expanduser(path))
    while True:
        dot = os.path.join(p, ".git")
        if os.path.isdir(dot):
            return Repo(p, dot, dot)
        if os.path.isfile(dot):
            text = (_read(dot) or "").strip()
            if not text.startswith("gitdir:"):
                return None
            gitdir = os.path.normpath(os.path.join(p, text[7:].strip()))
            common = (_read(os.path.join(gitdir, "commondir")) or "").strip()
            commondir = os.path.normpath(os.path.join(gitdir, common)) if common else gitdir
            return Repo(p, gitdir, commondir)
        parent = os.path.dirname(p)
        if parent == p:
            return None
        p = parent


def _resolve_dir(current, target):
    """Return the directory cd target leads to, or None when it can't be known."""
    if target is None:
        target = "~"
    if target == "-" or "$" in target or BACKTICK in target or "<expansion>" in target:
        return None
    return os.path.normpath(os.path.join(current, os.path.expanduser(target)))


def _git_subcommand(argv):
    """Return (subcommand, rest, -C dirs) of a git argv."""
    dirs, i = [], 1
    while i < len(argv) and argv[i].startswith("-"):
        if argv[i] == "-C" and i + 1 < len(argv):
            dirs.append(argv[i + 1])
            i += 2
        elif argv[i] in ("-c", "--git-dir", "--work-tree", "--namespace"):
            i += 2
        else:
            i += 1
    return (argv[i] if i < len(argv) else None), argv[i + 1:], dirs


def track_dirs(segments, cwd, odd=False):
    """Return one {"dir", "uncertain", "branch"} per segment, in order.

    The directory is cwd moved by earlier cd segments and by -C of git, make
    and tar. An unresolvable cd (a variable, cd -) keeps the last known
    directory and marks every later segment uncertain. branch is set after a
    checkout or switch that names the branch (-b, -c, or switch's argument);
    a plain checkout may name a file, so it only marks uncertainty. A command
    with subshells or background jobs that also holds a cd is uncertain."""
    out, current, uncertain, branch = [], cwd, False, None
    has_cd = any(s["argv"] and os.path.basename(s["argv"][0]) in ("cd", "pushd") for s in segments)
    for seg in segments:
        argv = seg["argv"]
        prog = os.path.basename(argv[0]) if argv else ""
        here, seen_branch = current, branch
        if prog in ("cd", "pushd"):
            args = [a for a in argv[1:] if not (a.startswith("-") and a != "-")]
            target = _resolve_dir(current, args[0] if args else None)
            if target is None:
                uncertain = True
            elif not seg["piped"]:
                current = target
        elif prog == "git":
            sub, rest, dirs = _git_subcommand(argv)
            for d in dirs:
                moved = _resolve_dir(here, d)
                if moved is None:
                    uncertain = True
                else:
                    here = moved
            if sub in ("checkout", "switch"):
                named = [rest[i + 1] for i, a in enumerate(rest[:-1]) if a in ("-b", "-B", "-c", "-C")]
                plain = [a for a in rest if not a.startswith("-")]
                if named:
                    branch = named[0]
                elif sub == "switch" and plain:
                    branch = plain[0]
                else:
                    uncertain = True
        elif prog in ("make", "tar"):
            for i, a in enumerate(argv[1:-1], 1):
                if a == "-C":
                    moved = _resolve_dir(here, argv[i + 1])
                    if moved is None:
                        uncertain = True
                    else:
                        here = moved
        out.append({"dir": here, "uncertain": uncertain or (odd and has_cd), "branch": seen_branch})
    return out


def self_test():
    import shutil
    import subprocess
    import tempfile

    failures = 0

    def check(label, got, want):
        nonlocal failures
        if got != want:
            failures += 1
            print(f"FAIL {label}: got {got!r}, want {want!r}")

    env = {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "SSH_"))}
    env.update({"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull, "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
                "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"})

    def git(cwd, *args):
        return subprocess.run(["git", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main", *args],
                              cwd=cwd, env=env, check=True, capture_output=True, text=True).stdout.strip()

    cases = [
        ("https://github.com/acme/repo.git", "github.com/acme/repo"),
        ("https://user:pw@GitHub.com/acme/repo", "github.com/acme/repo"),
        ("git@github.com:acme/repo.git", "github.com/acme/repo"),
        ("ssh://git@github.com:22/acme/repo.git/", "github.com/acme/repo"),
        ("https://gitlab.example.com/a/b/c.git", "gitlab.example.com/a/b/c"),
        ("/srv/git/repo.git", None), ("../repo", None), ("file:///srv/repo.git", None),
    ]
    for url, want in cases:
        check("remote " + url, normalise_remote(url)[0], want)
    check("userinfo stripped", normalise_remote("https://user:pw@github.com/a/b.git")[1], "https://github.com/a/b.git")
    for b, default, want in [
        ("main", "main", "default"), ("main", None, "default"), ("develop", "develop", "default"),
        ("release/1.2", "main", "protected"), ("production", "main", "protected"), ("prod-eu", "main", "protected"),
        ("hotfix/x", "main", "protected"), ("feat/x", "main", "feature"), ("master", "main", "protected"),
        (None, "main", "detached"),
    ]:
        check(f"class {b}/{default}", branch_class(b, default), want)
    check("config", parse_config('[remote "origin"]\n\turl = https://x/y.git # c\n[branch "a/b"]\n\tmerge = refs/heads/a/b\n'
                                 '[push]\n\tdefault = current\n[core]\n\tbare\n'),
          {("remote", "origin"): {"url": "https://x/y.git"}, ("branch", "a/b"): {"merge": "refs/heads/a/b"},
           ("push", None): {"default": "current"}, ("core", None): {"bare": "true"}})

    tmp = os.path.realpath(tempfile.mkdtemp(prefix="gitctx-"))
    try:
        check("outside a repo", find_repo(os.path.join(tmp, "nowhere", "deeper")), None)
        main = os.path.join(tmp, "main-repo")
        os.makedirs(main)
        git(main, "init", "-q")
        with open(os.path.join(main, "f"), "w") as f:
            f.write("x")
        git(main, "add", "f")
        git(main, "commit", "-q", "-m", "one")
        sha = git(main, "rev-parse", "HEAD")

        info = find_repo(main).info()
        check("no remote: key", info["repo_key"], "path:" + os.path.join(main, ".git"))
        check("no remote: url", info["remote_url"], None)
        check("no remote: branch", (info["branch"], info["head_sha"], info["branch_class"]), ("main", sha, "default"))
        check("no remote: upstream", (info["upstream"], info["worktree"], info["fetched_at"]), (None, None, None))

        git(main, "remote", "add", "origin", "https://user:pw@github.com/acme/repo.git")
        git(main, "update-ref", "refs/remotes/origin/main", sha)
        git(main, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
        git(main, "config", "branch.main.remote", "origin")
        git(main, "config", "branch.main.merge", "refs/heads/main")
        with open(os.path.join(main, ".git", "FETCH_HEAD"), "w") as f:
            f.write("")
        sub = os.path.join(main, "a", "b")
        os.makedirs(sub)
        info = find_repo(sub).info()
        check("main: key", info["repo_key"], "github.com/acme/repo")
        check("main: url", info["remote_url"], "https://github.com/acme/repo.git")
        check("main: default", (info["default_branch"], info["branch_class"]), ("main", "default"))
        check("main: upstream", (info["upstream"], info["upstream_sha"]), ("origin/main", sha))
        check("main: fetched", isinstance(info["fetched_at"], int), True)
        check("main: toplevel", info["toplevel"], main)

        git(main, "branch", "feat/x")
        wt = os.path.join(tmp, "wt")
        git(main, "worktree", "add", "-q", wt, "feat/x")
        winfo = find_repo(wt).info()
        check("worktree: linked", winfo["worktree"], wt)
        check("worktree: branch", (winfo["branch"], winfo["head_sha"], winfo["branch_class"]), ("feat/x", sha, "feature"))
        check("worktree: key shared", winfo["repo_key"], "github.com/acme/repo")
        check("worktree: main path", winfo["main_path"], main)
        check("worktree: default branch from commondir", winfo["default_branch"], "main")

        git(wt, "checkout", "-q", "--detach")
        dinfo = find_repo(wt).info()
        check("detached", (dinfo["branch"], dinfo["head_sha"], dinfo["branch_class"]), (None, sha, "detached"))

        git(main, "branch", "release/1.0")
        git(main, "pack-refs", "--all", "--prune")
        check("packed only: loose ref gone", os.path.exists(os.path.join(main, ".git", "refs", "heads", "release", "1.0")), False)
        repo = find_repo(main)
        check("packed: ref_sha", repo.ref_sha("refs/heads/release/1.0"), sha)
        check("packed: remote ref", repo.ref_sha("refs/remotes/origin/main"), sha)
        git(main, "checkout", "-q", "release/1.0")
        pinfo = find_repo(main).info()
        check("packed: HEAD branch", (pinfo["branch"], pinfo["head_sha"], pinfo["branch_class"]),
              ("release/1.0", sha, "protected"))
        check("missing ref", repo.ref_sha("refs/heads/nope"), None)
        check("traversal refused", repo.ref_sha("../config"), None)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    def seg(*argv, piped=False):
        return {"argv": list(argv), "via": [], "env": [], "piped": piped}

    home = os.path.expanduser("~")
    got = track_dirs([seg("cd", "~/CX/a"), seg("git", "push"), seg("cd", "../b"), seg("git", "-C", "/x", "push"),
                      seg("make", "-C", "sub", "all"), seg("ls")], "/w")
    check("track dirs", [g["dir"] for g in got],
          ["/w", os.path.join(home, "CX/a"), os.path.join(home, "CX/a"),
           "/x", os.path.join(home, "CX/b/sub"), os.path.join(home, "CX/b")])
    check("track certain", [g["uncertain"] for g in got], [False] * 6)
    got = track_dirs([seg("cd", "$X"), seg("git", "push")], "/w")
    check("track variable cd", [(g["dir"], g["uncertain"]) for g in got], [("/w", True), ("/w", True)])
    got = track_dirs([seg("cd", "-"), seg("ls")], "/w")
    check("track cd -", got[1]["uncertain"], True)
    got = track_dirs([seg("git", "checkout", "-b", "x"), seg("git", "push")], "/w")
    check("track checkout -b", [g["branch"] for g in got], [None, "x"])
    got = track_dirs([seg("git", "switch", "y"), seg("git", "push")], "/w")
    check("track switch", got[1]["branch"], "y")
    got = track_dirs([seg("git", "checkout", "file.txt"), seg("git", "push")], "/w")
    check("track plain checkout", (got[1]["branch"], got[1]["uncertain"]), (None, True))
    got = track_dirs([seg("cd", "x"), seg("ls")], "/w", odd=True)
    check("track odd with cd", got[1]["uncertain"], True)
    got = track_dirs([seg("cd", "x", piped=True), seg("ls")], "/w")
    check("piped cd is a subshell", got[1]["dir"], "/w")
    print(f"gitctx: {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv else 2)
