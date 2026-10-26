import sys, os, unittest, tempfile, subprocess, shutil, io, contextlib
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


class TestTrailingComments(unittest.TestCase):
    """行尾注释必须识别 —— 设计文档 §6 与 docs/repos.yaml.sample.yaml 的书写习惯
    就是 `fetch: submodule   # submodule | manifest`。"""

    YAML = (
        "version: 1\n"
        "repos:\n"
        "  - name: projects\n"
        "    url: https://github.com/yinchengwang/projects.git\n"
        "    fetch: submodule              # submodule | manifest\n"
        "    path: projects                # 相对 StillEvolving 根\n"
        "    must_contain: [engine, apps]  # 顶层目录\n"
        "    description: 工程仓           # 说明\n"
    )

    def test_strips_trailing_comment_from_scalar(self):
        repos = parse_repos(self.YAML)
        self.assertEqual(repos[0]["fetch"], "submodule")
        self.assertEqual(repos[0]["path"], "projects")
        self.assertEqual(repos[0]["description"], "工程仓")

    def test_strips_trailing_comment_from_inline_list(self):
        repos = parse_repos(self.YAML)
        self.assertEqual(repos[0]["must_contain"], ["engine", "apps"])

    def test_hash_inside_quotes_is_literal(self):
        text = ("version: 1\nrepos:\n  - name: x\n"
                "    description: 'a # b'\n"
                "    fetch: manifest\n")
        repos = parse_repos(text)
        self.assertEqual(repos[0]["description"], "a # b")


class TestCheckAllGate(unittest.TestCase):
    """check_all / main 才是真正的门 —— 8 条校验里原本有 6 条完全没有测试覆盖。

    这里用一个临时的最小工作树把每条规则都钉一遍。
    """

    REAL_SYNC = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "..", "reference", "scripts", "sync_catalog.py")

    CATALOG = (
        "projects:\n"
        "  - name: alpha\n"
        "    model: vector\n"
        "    tier: core\n"
        "    repository: https://example/alpha.git\n"
        "    license: MIT\n"
        "    status: active\n"
        "    commit: 1111111111111111111111111111111111111111\n"
        "    clone_url: https://example/alpha.git\n"
        "    pin_status: valid\n"
        "    source: mirror\n"
        "    notes:\n"
        "      - 说明\n"
        "  - name: beta\n"
        "    model: vector\n"
        "    tier: core\n"
        "    repository: https://example/beta.git\n"
        "    license: MIT\n"
        "    status: active\n"
        "    commit: 2222222222222222222222222222222222222222\n"
        "    clone_url: https://example/beta.git\n"
        "    pin_status: valid\n"
        "    source: mirror\n"
        "    notes:\n"
        "      - 说明\n"
        "  - name: gamma\n"
        "    model: vector\n"
        "    tier: core\n"
        "    repository: https://example/gamma.git\n"
        "    license: MIT\n"
        "    status: active\n"
        "    commit: null\n"
        "    clone_url: null\n"
        "    pin_status: unresolvable\n"
        "    source: none\n"
        "    notes:\n"
        "      - 说明\n"
    )

    MANIFEST = (
        "# model\tname\tclone_url\tcommit\tpin_status\n"
        "vector\talpha\thttps://example/alpha.git\t1111111111111111111111111111111111111111\tvalid\n"
        "vector\tbeta\thttps://example/beta.git\t2222222222222222222222222222222222222222\tvalid\n"
        "vector\tgamma\t-\t-\tunresolvable\n"
    )

    REPOS = (
        "version: 1\n"
        "repos:\n"
        "  - name: projects\n"
        "    url: https://github.com/yinchengwang/projects.git\n"
        "    fetch: submodule\n"
        "    path: projects\n"
        "    must_contain: [engine]\n"
        "    description: 工程仓\n"
        "  - name: reference\n"
        "    url: https://github.com/yinchengwang/reference.git\n"
        "    fetch: manifest\n"
        "    path: ../reference\n"
        "    must_contain: [reference, scripts]\n"
        "    description: 第三方源码镜像\n"
        "    upstream:\n"
        "      manifest: reference/catalog.yml\n"
        "      lockfile: reference/fetch-manifest.txt\n"
        "      script: scripts/fetch-reference.sh\n"
        "      total: 2\n"
    )

    def _tree(self, repos_yaml=None, catalog=None, manifest=None, parent_modules=True):
        """搭一个最小工作树：父仓 + 一个 submodule 仓 + 一个平级的 reference 仓。"""
        import shutil
        base = tempfile.mkdtemp()
        root = os.path.join(base, "StillEvolving")
        os.makedirs(root)
        subprocess.run(["git", "init", "-q", root], check=True, capture_output=True)

        proj = os.path.join(root, "projects")
        os.makedirs(os.path.join(proj, "engine"))
        subprocess.run(["git", "init", "-q", proj], check=True, capture_output=True)

        ref = os.path.join(base, "reference")
        os.makedirs(os.path.join(ref, "reference"))
        os.makedirs(os.path.join(ref, "scripts"))
        real_sync = os.path.normpath(self.REAL_SYNC)
        if os.path.exists(real_sync):
            shutil.copyfile(real_sync, os.path.join(ref, "scripts", "sync_catalog.py"))
        with open(os.path.join(ref, "reference", "catalog.yml"), "w",
                  encoding="utf-8", newline="") as fh:
            fh.write(self.CATALOG if catalog is None else catalog)
        with open(os.path.join(ref, "reference", "fetch-manifest.txt"), "w",
                  encoding="utf-8", newline="") as fh:
            fh.write(self.MANIFEST if manifest is None else manifest)
        with open(os.path.join(ref, ".gitmodules"), "w", encoding="utf-8", newline="") as fh:
            fh.write('[submodule "reference/vector/alpha"]\n'
                     "\tpath = reference/vector/alpha\n"
                     "\turl = https://gitee.com/mirrors/alpha.git\n")
        subprocess.run(["git", "init", "-q", ref], check=True, capture_output=True)

        with open(os.path.join(root, "repos.yaml"), "w", encoding="utf-8", newline="") as fh:
            fh.write(self.REPOS if repos_yaml is None else repos_yaml)
        if parent_modules:
            with open(os.path.join(root, ".gitmodules"), "w", encoding="utf-8", newline="") as fh:
                fh.write('[submodule "projects"]\n\tpath = projects\n'
                         "\turl = https://github.com/yinchengwang/projects.git\n")
        # 父仓的 fetch-reference.sh（upstream.script 指向它）
        with open(os.path.join(root, "scripts_fetch.sh"), "w", encoding="utf-8") as fh:
            fh.write("#!/bin/bash\n")
        os.makedirs(os.path.join(root, "scripts"), exist_ok=True)
        with open(os.path.join(root, "scripts", "fetch-reference.sh"), "w",
                  encoding="utf-8", newline="") as fh:
            fh.write("#!/bin/bash\n")
        return root

    def _run(self, root):
        from check_consistency import check_all
        return check_all(root)

    def test_clean_tree_has_no_problems(self):
        root = self._tree()
        problems, warnings = self._run(root)
        self.assertEqual(problems, [], problems)

    def test_missing_must_contain_is_reported(self):
        """校验 #4：must_contain 列的目录缺失必须报出来。"""
        root = self._tree()
        os.rmdir(os.path.join(root, "projects", "engine"))
        problems, _ = self._run(root)
        self.assertTrue(any("缺失顶层项" in p for p in problems), problems)

    def test_invalid_fetch_value_is_reported(self):
        """校验 #2/#3 不能因为 fetch 写错而被静默跳过。"""
        root = self._tree(repos_yaml=self.REPOS.replace(
            "fetch: submodule", "fetch: submodul", 1))
        problems, _ = self._run(root)
        self.assertTrue(any("fetch 取值非法" in p for p in problems), problems)

    def test_missing_path_is_reported(self):
        """缺 path 时不能默默去检查父仓根目录。"""
        root = self._tree(repos_yaml=self.REPOS.replace("    path: projects\n", "", 1))
        problems, _ = self._run(root)
        self.assertTrue(any("缺少 path" in p for p in problems), problems)

    def test_missing_upstream_total_is_reported(self):
        """校验 #5：upstream.total 缺失不能静默跳过条目数校验。"""
        root = self._tree(repos_yaml=self.REPOS.replace("      total: 2\n", "", 1))
        problems, _ = self._run(root)
        self.assertTrue(any("缺少 total" in p for p in problems), problems)

    def test_mirror_count_mismatch_is_reported(self):
        """校验 #5：source=mirror 的条目数必须等于 upstream.total。"""
        root = self._tree(repos_yaml=self.REPOS.replace("total: 2", "total: 3", 1))
        problems, _ = self._run(root)
        self.assertTrue(any("source=mirror" in p for p in problems), problems)

    def test_illegal_pin_status_is_reported(self):
        """校验 #6：pin_status 必须在 {valid,broken,unresolvable} 内。"""
        bad = self.CATALOG.replace("pin_status: valid", "pin_status: whatever", 1)
        root = self._tree(catalog=bad)
        problems, _ = self._run(root)
        self.assertTrue(any("pin_status 非法" in p for p in problems), problems)

    def test_manifest_mismatch_is_reported(self):
        """校验 #7：fetch-manifest.txt 必须与 catalog 生成结果一致。"""
        root = self._tree(manifest=self.MANIFEST.replace("alpha", "delta", 1))
        problems, _ = self._run(root)
        self.assertTrue(any("fetch-manifest" in p for p in problems), problems)

    def test_missing_manifest_is_reported(self):
        root = self._tree()
        os.remove(os.path.join(os.path.dirname(root), "reference",
                               "reference", "fetch-manifest.txt"))
        problems, _ = self._run(root)
        self.assertTrue(any("manifest 不存在" in p for p in problems), problems)

    def test_missing_reference_dir_is_reported(self):
        """校验 #3：manifest 仓必须有 reference/ 源码层目录。"""
        root = self._tree()
        shutil.rmtree(os.path.join(os.path.dirname(root), "reference", "reference"))
        problems, _ = self._run(root)
        self.assertTrue(any("reference/" in p for p in problems), problems)

    def test_divergence_is_warning_not_error(self):
        """校验 #8：clone_url 与 .gitmodules 分歧只告警，退出码仍是 0。"""
        root = self._tree()
        problems, warnings = self._run(root)
        self.assertTrue(any("clone_url 与 .gitmodules url 分歧" in w for w in warnings), warnings)
        self.assertEqual(problems, [], problems)

    def test_main_exit_codes(self):
        from check_consistency import main
        import io, contextlib
        root = self._tree()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = main(["--root", root])
        self.assertEqual(rc, 0, out.getvalue())
        os.rmdir(os.path.join(root, "projects", "engine"))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = main(["--root", root])
        self.assertEqual(rc, 1, out.getvalue())


class TestBootstrapEncoding(unittest.TestCase):
    """bootstrap.ps1 必须带 UTF-8 BOM —— 否则 Windows PowerShell 5.1 会按 ANSI
    码页解码，中文吞掉引号 → 整段 ParserError，脚本根本不会执行。"""

    def test_bootstrap_ps1_has_utf8_bom(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bootstrap.ps1")
        with open(path, "rb") as fh:
            data = fh.read()
        self.assertTrue(data.startswith(b"\xef\xbb\xbf"),
                        "bootstrap.ps1 缺少 UTF-8 BOM（Windows PowerShell 5.1 会按 ANSI 解析）")

    def test_bootstrap_sh_has_no_recursive_submodule_init(self):
        """G1：bootstrap 绝不能递归初始化 submodule（会拉 25 GB）。
        只看**命令行**，注释里提到这个词不算。"""
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bootstrap.sh")
        with open(path, "r", encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        commands = [l.strip() for l in lines if l.strip().startswith("git ")]
        self.assertTrue(commands, "bootstrap.sh 里没有 git 命令")
        for cmd in commands:
            self.assertNotIn("--recursive", cmd, cmd)
            self.assertNotIn("--init --recursive", cmd, cmd)


if __name__ == "__main__":
    unittest.main()
