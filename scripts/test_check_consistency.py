import sys, os, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_consistency import parse_repos, check_must_contain

REPOS_YAML = """
version: 1
repos:
  - name: projects
    url: https://github.com/yinchengwang/projects.git
    fetch: submodule
    path: projects
    must_contain: [engine, apps, docs]
    description: 工程仓
"""


class TestParseRepos(unittest.TestCase):
    def test_parses_repos(self):
        repos = parse_repos(REPOS_YAML)
        self.assertEqual(len(repos), 1)
        r = repos[0]
        self.assertEqual(r["name"], "projects")
        self.assertEqual(r["fetch"], "submodule")
        self.assertEqual(r["path"], "projects")
        self.assertEqual(r["must_contain"], ["engine", "apps", "docs"])

    def test_parses_relative_parent_path(self):
        """reference 的 path 是 ../reference（相对父仓根的兄弟目录）。"""
        text = ("version: 1\nrepos:\n  - name: reference\n"
                "    path: ../reference\n    fetch: manifest\n"
                "    must_contain: [reference, docs, scripts]\n")
        repos = parse_repos(text)
        self.assertEqual(repos[0]["path"], "../reference")


class TestMustContain(unittest.TestCase):
    def test_reports_missing(self):
        """F4: must_contain 列的目录缺失必须被报出来。"""
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            os.mkdir(os.path.join(d, "engine"))
            os.mkdir(os.path.join(d, "docs"))
            missing = check_must_contain(d, ["engine", "apps", "docs"])
            self.assertEqual(missing, ["apps"])

    def test_subset_not_equality(self):
        """must_contain 是子集断言：仓里多出的目录不算违规。"""
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            os.mkdir(os.path.join(d, "engine"))
            os.mkdir(os.path.join(d, "extra_dir"))
            missing = check_must_contain(d, ["engine"])
            self.assertEqual(missing, [])

    def test_all_present(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            for n in ("engine", "apps"):
                os.mkdir(os.path.join(d, n))
            self.assertEqual(check_must_contain(d, ["engine", "apps"]), [])


class TestParseReposRealShape(unittest.TestCase):
    """真实的 repos.yaml 还有嵌套映射、列表、块标量 —— 都要能解析。"""

    YAML = """
version: 1
repos:
  - name: projects
    url: https://github.com/yinchengwang/projects.git
    fetch: submodule
    path: projects
    role: 工程仓
    must_contain: [engine, apps, docs, .ai, vendor]
    description: 自研数据库/搜索引擎引擎
    known_duplication:
      - path: vendor/third_part/googletest
        also_in: learning/third_part/googletest
        note: 两仓各有一份 googletest，本次刻意保留两份不合并

  - name: reference
    url: https://github.com/yinchengwang/reference.git
    fetch: manifest
    path: ../reference
    role: 第三方源码镜像 + 源码笔记
    must_contain: [reference, docs, scripts]
    description: 95 个第三方库的按需镜像
    upstream:
      manifest: reference/catalog.yml
      lockfile: reference/fetch-manifest.txt
      script: scripts/fetch-reference.sh
      commit_field: commit
      pin_status_field: pin_status
      total: 95
      notes: |
        reference 不作为 submodule 挂载。
        递归克隆会拉取 25 GB / 53.6 万文件。
"""

    def setUp(self):
        self.repos = parse_repos(self.YAML)

    def test_parses_both_repos(self):
        self.assertEqual(len(self.repos), 2)
        self.assertEqual([r["name"] for r in self.repos], ["projects", "reference"])

    def test_parses_nested_list_of_mappings(self):
        dup = self.repos[0]["known_duplication"]
        self.assertEqual(len(dup), 1)
        self.assertEqual(dup[0]["path"], "vendor/third_part/googletest")
        self.assertEqual(dup[0]["also_in"], "learning/third_part/googletest")

    def test_parses_nested_mapping(self):
        up = self.repos[1]["upstream"]
        self.assertEqual(up["manifest"], "reference/catalog.yml")
        self.assertEqual(up["lockfile"], "reference/fetch-manifest.txt")
        self.assertEqual(up["script"], "scripts/fetch-reference.sh")
        self.assertEqual(up["commit_field"], "commit")
        self.assertEqual(up["pin_status_field"], "pin_status")

    def test_parses_block_scalar(self):
        notes = self.repos[1]["upstream"]["notes"]
        self.assertIn("25 GB", notes)
        self.assertIn("submodule", notes)

    def test_keeps_dot_prefixed_must_contain(self):
        """.ai 这类隐藏目录必须原样保留。"""
        self.assertIn(".ai", self.repos[0]["must_contain"])


class TestResolveUpstreamPaths(unittest.TestCase):
    """Ruling 20：upstream.manifest / lockfile 相对 reference 仓根，
    upstream.script 相对父仓根 —— 三个字段的路径基准不同。"""

    def test_manifest_and_lockfile_resolve_against_reference_root(self):
        from check_consistency import resolve_upstream_paths
        entry = {"name": "reference", "path": "../reference",
                 "upstream": {"manifest": "reference/catalog.yml",
                              "lockfile": "reference/fetch-manifest.txt",
                              "script": "scripts/fetch-reference.sh"}}
        parent = os.path.join("C:", "code", "StillEvolving")
        out = resolve_upstream_paths(entry, parent)
        self.assertEqual(out["manifest"],
                         os.path.join("C:", "code", "reference", "reference", "catalog.yml"))
        self.assertEqual(out["lockfile"],
                         os.path.join("C:", "code", "reference", "reference", "fetch-manifest.txt"))

    def test_script_resolves_against_parent_root(self):
        from check_consistency import resolve_upstream_paths
        entry = {"name": "reference", "path": "../reference",
                 "upstream": {"script": "scripts/fetch-reference.sh"}}
        parent = os.path.join("C:", "code", "StillEvolving")
        out = resolve_upstream_paths(entry, parent)
        self.assertEqual(out["script"],
                         os.path.join("C:", "code", "StillEvolving", "scripts", "fetch-reference.sh"))


class TestCloneUrlDivergence(unittest.TestCase):
    """clone_url 与 .gitmodules 的 url 允许分歧（mysql 就是这种情况）——
    但必须报出来，且只告警不报错。"""

    def test_reports_divergent_entries(self):
        from check_consistency import check_clone_url_divergence
        entries = [
            {"name": "mysql", "clone_url": "https://github.com/mysql/mysql-server.git"},
            {"name": "postgres", "clone_url": "https://github.com/postgres/postgres.git"},
        ]
        gitmodules = {
            "reference/relational/mysql": "https://gitee.com/yinchengwang_admin/mysql-server.git",
            "reference/relational/postgres": "https://github.com/postgres/postgres.git",
        }
        divergent = check_clone_url_divergence(entries, gitmodules,
                                               {"mysql": "relational"})
        self.assertEqual(divergent, ["mysql"])


if __name__ == "__main__":
    unittest.main()
