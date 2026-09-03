from __future__ import annotations

from io import StringIO
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from zenlang import (
    BUNDLE_VERSION,
    GRAMMAR_VERSION,
    IR_VERSION,
    ZenLangError,
    check_tree,
    compile_tree,
    parse,
    parse_file,
)
from zenlang.cli import main
from zenlang.compiler import (
    CompilationError,
    compile_document,
    compile_zcfg,
    compile_zmdl,
    compile_zpkg,
    compile_zstr,
)
from zenlang.emitter import (
    NixEmissionError,
    NixEmitter,
    emit_expression,
    emit_nix_data,
    emit_statement,
    quote_nix_string,
    semantic_descriptor,
)
from zenlang.model import Literal, Span


FIXTURES = Path(__file__).parent / "fixtures"


def expression(source: str, kind: str = "zpkg"):
    return (
        parse(
            f"value = {source};",
            f"expression.{kind}",
            validate_semantics=False,
        )
        .statements[0]
        .value
    )


class NixEmitterTests(unittest.TestCase):
    def test_literals_strings_paths_references_variables_lists_and_attrsets(
        self,
    ) -> None:
        cases = (
            ("null", "null"),
            ("true", "true"),
            ("42", "42"),
            ("3.5", "3.5"),
            ("1.2.3Nb", '"1.2.3Nb"'),
            ('"a\\n\\"b ${$v.name}"', '"a\\n\\"b ${name}"'),
            (
                "./source",
                '{\n  __zenlangType = "path";\n  kind = "relative";\n  value = "./source";\n}',
            ),
            (
                "/etc/example",
                '{\n  __zenlangType = "path";\n  kind = "absolute";\n  value = "/etc/example";\n}',
            ),
            ("source.github", "source.github"),
            ("$pkgs.zenos.git", "pkgs.zenos.git"),
            ("$name", '"expression"'),
            ("[ 1 true ]", "[\n  1\n  true\n]"),
            ("{ z = 2; a = 1; }", "{\n  z = 2;\n  a = 1;\n}"),
        )
        for source, expected in cases:
            with self.subTest(source=source):
                self.assertEqual(expected, emit_expression(expression(source)))

    def test_all_operator_and_control_expression_forms_are_parenthesized(self) -> None:
        cases = (
            ("!true", "(!true)"),
            ("1 + 2 * 3", "(1 + (2 * 3))"),
            ("settings.value", "settings.value"),
            ("settings.value or 4", "(settings.value or 4)"),
            ("fn 1 2", "((fn 1) 2)"),
            ("if true then 1 else 2", "(if true then 1 else 2)"),
            ("let value = 1; in value", "(let\n  value = 1;\nin value)"),
            ("with $pkgs; git", "(with pkgs.zenos; git)"),
            ("value: value + 1", "(value: (value + 1))"),
            ("{ value ? 1, ... }: value", "({ value ? 1, ... }: value)"),
        )
        for source, expected in cases:
            with self.subTest(source=source):
                self.assertEqual(expected, emit_expression(expression(source)))

    def test_selection_dynamic_segments_and_structural_values(self) -> None:
        selected = expression("($v.record).field")
        self.assertEqual("((record)).field", emit_expression(selected))

        marker = expression("(alias legacy.($v.name))", "zstr")
        emitted = emit_expression(marker)
        self.assertIn('kind = "alias";', emitted)
        self.assertIn('type = "structural-marker";', emitted)
        self.assertIn('type = "dynamic";', emitted)

        enabled = expression("enableOption { _meta.default = true; }", "zmdl")
        self.assertIn('__zenlangType = "enable-option";', emit_expression(enabled))

        marker_statement = parse(
            "(packages) = { enabled = true; };",
            "marker.zstr",
        ).statements[0]
        self.assertIn("marker =", emit_statement(marker_statement))
        self.assertIn('kind = "packages";', emit_statement(marker_statement))

    def test_every_statement_family_emits_a_nix_fragment(self) -> None:
        assignment = parse("value = 1;", "s.zpkg").statements[0]
        imported = parse('_import data = "data.zpkg";', "s.zpkg", validate_semantics=False).statements[0]
        local = parse("_let x: $type.int = 1;", "s.zpkg").statements[0]
        conditional = parse("if true { value = 1; };", "s.zcfg").statements[0]
        action = (
            parse("option = { _meta.type = $type.bool; s! [ true ] { value = 1; }; };", "s.zmdl")
            .statements[0]
            .value.statements[1]
        )
        inherited = expression("{ inherit (source) value; }").statements[0]

        self.assertEqual("value = 1;", emit_statement(assignment))
        with self.assertRaises(NixEmissionError):
            emit_statement(imported)
        self.assertEqual("x = 1;", emit_statement(local))
        self.assertEqual(
            "config = lib.mkIf true {\n  value = 1;\n};", emit_statement(conditional)
        )
        self.assertIn("config = lib.mkIf", emit_statement(action))
        self.assertEqual("inherit (source) value;", emit_statement(inherited))

    def test_safe_escaping_identifiers_data_and_failures(self) -> None:
        self.assertEqual(
            '"a\\\\b\\"c\\n\\${unsafe}"', quote_nix_string('a\\b"c\n${unsafe}')
        )
        self.assertEqual(
            '{\n  a = 1;\n  "not safe" = true;\n}',
            emit_nix_data({"not safe": True, "a": 1}),
        )
        with self.assertRaises(NixEmissionError):
            quote_nix_string("bad\x00value")
        with self.assertRaises(NixEmissionError) as raised:
            emit_expression(Literal(float("inf"), "float", Span.point("manual.zpkg")))
        self.assertEqual("manual.zpkg", raised.exception.span.source)
        with self.assertRaises(NixEmissionError):
            NixEmitter().binding_name("not safe")

    def test_semantic_descriptors_are_span_free_and_stable(self) -> None:
        described = semantic_descriptor(expression('"hello ${1 + 2}"'))
        self.assertEqual("string", described["type"])
        self.assertEqual("interpolation", described["parts"][1]["type"])
        self.assertNotIn("span", repr(described))


class ZcfgCompilerTests(unittest.TestCase):
    def test_simple_output_matches_the_current_root_and_sorting_contract(self) -> None:
        document = parse(
            'system.enabled = true; legacy.networking.hostName = "zen"; system.name = "x";',
            "host.zcfg",
        )
        output = compile_zcfg(document)
        self.assertIn("{ pkgs, lib ? pkgs.lib, config ?", output)
        self.assertIn('name = "host";', output)
        self.assertIn('hostName = "zen";', output)
        self.assertIn("zenos = {", output)

    def test_conditions_imports_and_locals_become_a_module_merge(self) -> None:
        source = """
_import "base.zcfg";
_let enabled: $type.bool = true;
value = $v.enabled;
if $cfg.feature.enable or false { legacy.services.demo.enable = true; };
"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "base.zcfg").write_text("base = true;", encoding="utf-8")
            source_path = root / "host.zcfg"
            source_path.write_text(source, encoding="utf-8")
            output = compile_zcfg(parse_file(source_path))
        self.assertIn("{ pkgs, lib ? pkgs.lib, config ?", output)
        self.assertNotIn("import ", output)
        self.assertIn("base = true;", output)
        self.assertIn("enabled = true;", output)
        self.assertIn("lib.mkIf (config.zenos.feature.enable or false)", output)
        self.assertIn("services = {", output)
        self.assertIn("demo = {", output)

    def test_conflicting_assignments_fail_at_compile_time(self) -> None:
        sources = (
            "a = 1; a.b = 2;",
            "legacy.zenos.forbidden = true;",
            "legacy = { zenos.forbidden = true; };",
        )
        for source in sources:
            with self.subTest(source=source), self.assertRaises(CompilationError):
                compile_zcfg(parse(source, "bad.zcfg"))

    def test_imports_merge_in_order_and_bound_imports_are_descriptors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "first.zcfg").write_text("value = 1; first = true;", encoding="utf-8")
            (root / "second.zcfg").write_text("value = 2; second = true;", encoding="utf-8")
            (root / "bound.zcfg").write_text("bound = true;", encoding="utf-8")
            entry = root / "entry.zcfg"
            entry.write_text(
                '_import "first.zcfg"; _import "second.zcfg"; _import data: $type.set [ $type.bool ] = "bound.zcfg"; value = 3; selected = $v.data;',
                encoding="utf-8",
            )
            output = compile_zcfg(parse_file(entry))
            self.assertIn("value = 3;", output)
            self.assertIn("first = true;", output)
            self.assertIn("second = true;", output)
            self.assertIn('kind = "zcfg";', output)
            self.assertNotIn("import ", output)

            entry.write_text('_import "first.zcfg"; value = "bad";', encoding="utf-8")
            with self.assertRaises(ZenLangError) as raised:
                parse_file(entry)
            self.assertEqual("ZEN218", raised.exception.diagnostic.code)

            (root / "first.zcfg").write_text("_let same: $type.int = 1;", encoding="utf-8")
            (root / "second.zcfg").write_text("_let same: $type.int = 2;", encoding="utf-8")
            entry.write_text('_import "first.zcfg"; _import "second.zcfg";', encoding="utf-8")
            with self.assertRaises(ZenLangError) as raised:
                parse_file(entry)
            self.assertEqual("ZEN218", raised.exception.diagnostic.code)

    def test_compilation_errors_keep_the_offending_source_span(self) -> None:
        document = parse("ok = true; value = 1; value.child = 2;", "span.zcfg")
        with self.assertRaises(CompilationError) as raised:
            compile_zcfg(document)
        self.assertEqual(1, raised.exception.span.start.line)
        self.assertGreater(raised.exception.span.start.column, 1)

    def test_nested_conditions_combine_their_guards(self) -> None:
        document = parse(
            "outer = { if $cfg.first or false { if $cfg.second or false { value = true; }; }; };",
            "nested.zcfg",
        )
        output = compile_zcfg(document)
        self.assertIn("config.zenos.first or false", output)
        self.assertIn("config.zenos.second or false", output)
        self.assertIn("outer = {", output)


class ZmdlCompilerTests(unittest.TestCase):
    def test_options_metadata_and_all_action_routes(self) -> None:
        source = """
_meta.brief = "Desktop module";
enable = enableOption {
  _meta.default = true;
  _meta.brief = "Enable desktop";
  s! [ ($cfg.ready or false) ] { services.demo.enable = true; };
  u! { home.sessionVariables.DEMO = "1"; };
  !! { environment.variables.DEMO = "1"; };
  s!! { assertions = [ ]; };
};
"""
        output = compile_zmdl(parse(source, "desktop.zmdl"), target="system")
        self.assertIn("options.zenos.desktop", output)
        self.assertIn("enable = lib.mkOption", output)
        self.assertIn("type = lib.types.bool;", output)
        self.assertIn("default = true;", output)
        self.assertIn('description = "Enable desktop";', output)
        self.assertIn("lib.mkIf ((cfg.enable) && (((config.zenos.ready or false))))", output)
        self.assertIn("home-manager.sharedModules", output)
        self.assertIn("lib.mkMerge", output)
        self.assertIn("_module.args.zenlang.descriptors.desktop", output)
        self.assertIn("statements = [", output)

    def test_typed_options_and_freeforms_compile(self) -> None:
        source = """
port = { _meta.type = $type.int; _meta.default = 22; };
names = { _meta.type = $type.list [ $type.string ]; };
(freeform user) = {
  _meta.brief = "User ${$f.user}";
  s!! { users.users.($f.user).isNormalUser = true; };
};
"""
        output = compile_zmdl(parse(source, "accounts.zmdl"), target="system")
        self.assertIn(
            "port = lib.mkOption { type = lib.types.int; default = 22; }", output
        )
        self.assertIn("(lib.types.listOf lib.types.str)", output)
        self.assertIn(
            "user = lib.mkOption { type = lib.types.attrsOf lib.types.anything;", output
        )
        self.assertIn("lib.mapAttrsToList (user: _zenValue:", output)
        self.assertIn("users.users.${user}.isNormalUser", output)

    def test_canonical_zmdl_is_deterministic(self) -> None:
        document = parse_file(FIXTURES / "gnome.zmdl")
        self.assertEqual(
            compile_zmdl(document, target="system"),
            compile_zmdl(document, target="system"),
        )

    def test_generic_actions_route_only_to_the_explicit_target(self) -> None:
        document = parse("enable = enableOption { !! { value = true; }; };", "route.zmdl")
        system = compile_zmdl(document, target="system")
        user = compile_zmdl(document, target="user")
        self.assertNotIn("home-manager.sharedModules", system)
        self.assertIn("home-manager.sharedModules", user)

    def test_module_local_aliases_are_retained_in_the_descriptor(self) -> None:
        document = parse(
            '(alias legacy.demo.enable) = { target = "nixos"; path = "services.demo.enable"; type = $type.bool; };',
            "alias.zmdl",
        )
        output = compile_zmdl(document, target="system")
        self.assertIn("aliases = [", output)
        self.assertIn('value = "legacy";', output)


class ZpkgCompilerTests(unittest.TestCase):
    def test_interface_mode_resolves_ordered_dependency_cascades(self) -> None:
        source = """
_meta = {
  version = "1";
  zenosVersion = 1.2.3;
  deps = {
    global = [ $pkgs.zenos.a $pkgs.zenos.b ];
    build ++ [ $pkgs.zenos.compiler ];
    run -- [ $pkgs.zenos.b ];
    run ++ [ $pkgs.zenos.c ];
    export = [ $pkgs.zenos.exported ];
  };
};
_src = $src.local { path = ./.; };
_build = { type = $type.cargo; command = "build"; };
"""
        output = compile_zpkg(parse(source, "demo.zpkg"), mode="interface")
        self.assertIn('id = "$pkgs.zenos.c";', output)
        self.assertIn("export = [", output)
        self.assertIn("minVersion = null", output)
        self.assertIn('type = "variable";', output)
        self.assertNotIn("zenRuntime", output)
        self.assertNotIn("globalDependencies", output)
        self.assertTrue(output.endswith("}\n"))
        self.assertNotIn("zenRuntime.buildPackage descriptor", output)

    def test_build_mode_enforces_minimum_version_and_uses_runtime(self) -> None:
        document = parse_file(FIXTURES / "bat.zpkg")
        output = compile_zpkg(document, mode="build")
        self.assertIn("assert zenosVersion != null;", output)
        self.assertIn('assert lib.versionAtLeast zenosVersion "1.0.0Nb";', output)
        self.assertIn("assert zenRuntime != null;", output)
        self.assertTrue(output.endswith("zenRuntime.buildPackage descriptor\n"))
        self.assertIn("zenRuntime.resolveDependencies", output)
        self.assertNotIn("importPackage", output)
        self.assertIn("statements = [", output)

    def test_explicit_min_version_takes_precedence(self) -> None:
        document = parse(
            "_meta.zenosVersion = 1.0.0; _meta.minVersion = 2.0.0;",
            "versioned.zpkg",
        )
        output = compile_zpkg(document, mode="build")
        self.assertIn('lib.versionAtLeast zenosVersion "2.0.0"', output)

    def test_invalid_mode_is_rejected(self) -> None:
        with self.assertRaises(CompilationError):
            compile_zpkg(parse("value = true;", "value.zpkg"), mode="unknown")

    def test_dependency_deduplication_and_path_segment_identity(self) -> None:
        document = parse(
            '_meta.deps = { global = [ $pkgs.zenos.a $pkgs.zenos.a ]; }; "a.b" = 1; a.b = 2;',
            "paths.zpkg",
        )
        output = compile_zpkg(document, mode="interface")
        self.assertIn('id = "$pkgs.zenos.a";', output)
        self.assertEqual(4, output.count('id = "$pkgs.zenos.a";'))
        self.assertIn('"a.b"', output)
        self.assertIn('value = "a";', output)


class ZstrCompilerTests(unittest.TestCase):
    def test_structure_is_a_versioned_runtime_descriptor(self) -> None:
        output = compile_zstr(parse_file(FIXTURES / "typed-aliases.zstr"))
        self.assertIn('descriptorVersion = "zenlang.semantic/1";', output)
        self.assertIn('kind = "zstr";', output)
        self.assertIn('kind = "alias";', output)
        self.assertIn('type = "lambda";', output)
        self.assertNotIn("span =", output)

    def test_descriptor_does_not_depend_on_source_path(self) -> None:
        source = "(packages) = { enabled = true; };"
        first = compile_zstr(parse(source, "first.zstr"))
        second = compile_zstr(parse(source, "/different/second.zstr"))
        self.assertEqual(first, second)


class CompilerIntegrationTests(unittest.TestCase):
    def test_dispatches_all_document_kinds_and_checks_specific_backends(self) -> None:
        self.assertIn("zenos", compile_document(parse("value = true;", "a.zcfg")))
        self.assertIn(
            "mkOption",
            compile_document(parse("value = true;", "a.zmdl"), target="system"),
        )
        self.assertIn(
            "buildPackage", compile_document(parse("value = true;", "a.zpkg"))
        )
        self.assertIn(
            'kind = "zstr"', compile_document(parse("value = true;", "a.zstr"))
        )
        with self.assertRaises(CompilationError):
            compile_zcfg(parse("value = true;", "wrong.zpkg"))

    @unittest.skipUnless(
        shutil.which("nix-instantiate"), "nix-instantiate is unavailable"
    )
    def test_all_canonical_outputs_are_accepted_by_the_nix_parser(self) -> None:
        outputs = (
            compile_zcfg(parse_file(FIXTURES / "host.zcfg")),
            compile_zmdl(parse_file(FIXTURES / "gnome.zmdl"), target="system"),
            compile_zpkg(parse_file(FIXTURES / "bat.zpkg"), mode="interface"),
            compile_zpkg(parse_file(FIXTURES / "bat.zpkg"), mode="build"),
            compile_zstr(parse_file(FIXTURES / "structure.zstr")),
            compile_zstr(parse_file(FIXTURES / "typed-aliases.zstr")),
        )
        for output in outputs:
            with self.subTest(first_line=output.splitlines()[0]):
                result = subprocess.run(
                    ["nix-instantiate", "--store", "dummy://", "--parse", "-"],
                    input=output,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(0, result.returncode, result.stderr)


class CompilerCliTests(unittest.TestCase):
    def test_compile_supports_all_kinds_and_zpkg_modes(self) -> None:
        cases = (
            ("zmdl", "value = true;", None, "mkOption"),
            ("zpkg", "value = true;", "interface", 'kind = "zpkg"'),
            ("zpkg", "value = true;", "build", "buildPackage descriptor"),
            ("zstr", "value = true;", None, 'kind = "zstr"'),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for index, (suffix, source_text, mode, expected) in enumerate(cases):
                with self.subTest(suffix=suffix, mode=mode):
                    source = root / f"source-{index}.{suffix}"
                    source.write_text(source_text, encoding="utf-8")
                    arguments = ["compile", str(source)]
                    if suffix == "zmdl":
                        arguments.extend(("--target", "system"))
                    if mode is not None:
                        arguments.extend(("--mode", mode))
                    stdout = StringIO()
                    self.assertEqual(0, main(arguments, stdout, StringIO()))
                    self.assertIn(expected, stdout.getvalue())

    def test_zcfg_compile_accepts_legacy_import_with_a_warning(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "base.zcfg").write_text(
                "legacy.networking.hostName = \"zen\";\n", encoding="utf-8"
            )
            source = root / "system.zcfg"
            source.write_text(
                "import ./base.zcfg;\nsystem.enabled = true;\n", encoding="utf-8"
            )
            actual = StringIO()
            stderr = StringIO()

            self.assertEqual(0, main(["compile", str(source)], actual, stderr))
            self.assertIn("networking", actual.getvalue())
            self.assertNotIn("import ", actual.getvalue())
            self.assertIn("ZEN214", stderr.getvalue())

    def test_mode_is_rejected_for_non_zpkg_sources(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "module.zmdl"
            source.write_text("value = true;", encoding="utf-8")
            stderr = StringIO()
            self.assertEqual(
                1,
                main(
                    ["compile", str(source), "--mode", "interface"],
                    StringIO(),
                    stderr,
                ),
            )
            self.assertIn("--mode is only valid for .zpkg", stderr.getvalue())

    def test_zmdl_cli_requires_an_explicit_target(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "module.zmdl"
            source.write_text("value = true;", encoding="utf-8")
            stderr = StringIO()
            self.assertEqual(1, main(["compile", str(source)], StringIO(), stderr))
            self.assertIn("--target is required", stderr.getvalue())

    def test_cli_preserves_backend_error_spans(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "bad.zpkg"
            source.write_text("value = true;\n_meta.nested.field = 1;\n", encoding="utf-8")
            stderr = StringIO()
            self.assertEqual(
                1,
                main(["compile", str(source), "--mode", "interface"], StringIO(), stderr),
            )
            self.assertIn(f"{source}:2:", stderr.getvalue())


class TreeCompilerTests(unittest.TestCase):
    def _write_tree(self, root: Path) -> None:
        nested = root / "nested"
        nested.mkdir()
        (root / "system.zcfg").write_text(
            "system.enabled = true; if true { system.checked = true; };",
            encoding="utf-8",
        )
        (nested / "module.zmdl").write_text("value = true;", encoding="utf-8")
        (nested / "package.zpkg").write_text("value = true;", encoding="utf-8")
        (root / "structure.zstr").write_text("(zmdl nested.module) = { };", encoding="utf-8")
        (root / "ignored.txt").write_text("value = false;", encoding="utf-8")

    def test_tree_bundle_is_sorted_versioned_span_free_and_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self._write_tree(root)

            checked = check_tree(root)
            self.assertEqual(
                [
                    "nested/module.zmdl",
                    "nested/package.zpkg",
                    "structure.zstr",
                    "system.zcfg",
                ],
                list(checked),
            )
            first = compile_tree(root, mode="interface")
            second = compile_tree(root, mode="interface")
            self.assertEqual(first, second)
            self.assertEqual(BUNDLE_VERSION, first["bundleVersion"])
            self.assertEqual(GRAMMAR_VERSION, first["grammarVersion"])
            self.assertEqual(IR_VERSION, first["irVersion"])
            self.assertEqual(list(checked), [item["path"] for item in first["sources"]])
            self.assertNotIn('"span"', json.dumps(first, sort_keys=True))
            self.assertEqual("nested/module", first["structure"]["attachments"][0]["module"])
            for source in first["sources"]:
                self.assertEqual(source["kind"], source["descriptor"]["kind"])
                self.assertTrue(source["compiledNix"])

    def test_fixture_tree_applies_attachments_and_typed_aliases(self) -> None:
        bundle = compile_tree(FIXTURES, mode="interface")
        gnome = next(source for source in bundle["sources"] if source["path"] == "gnome.zmdl")
        self.assertIn('modulePath = [\n      "desktop"', gnome["compiledNix"])
        attachment = next(
            item for item in bundle["structure"]["attachments"] if item["module"] == "gnome"
        )
        self.assertEqual(["desktop"], attachment["path"])
        self.assertTrue(bundle["structure"]["aliases"])
        self.assertIn(
            ["ssh", "implementation", "enable"],
            [alias["path"] for alias in bundle["structure"]["aliases"]],
        )

    def test_tree_imports_use_the_explicit_root(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            nested = root / "nested"
            nested.mkdir()
            (root / "shared.zmdl").write_text("shared = true;", encoding="utf-8")
            (nested / "entry.zmdl").write_text(
                '_import "../shared.zmdl"; local = true;', encoding="utf-8"
            )
            self.assertEqual(2, len(check_tree(root)))

    def test_tree_skips_symlink_directories(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            real = root / "real"
            real.mkdir()
            (real / "source.zstr").write_text("value = true;", encoding="utf-8")
            (root / "linked").symlink_to(real, target_is_directory=True)
            self.assertEqual(["real/source.zstr"], list(check_tree(root)))

    def test_tree_rejects_case_collisions_and_file_count_overflow(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Name.zstr").write_text("value = true;", encoding="utf-8")
            (root / "name.ZSTR").write_text("value = false;", encoding="utf-8")
            with self.assertRaisesRegex(CompilationError, "case-colliding"):
                check_tree(root)

            (root / "name.ZSTR").unlink()
            (root / "other.zpkg").write_text("value = true;", encoding="utf-8")
            with patch("zenlang.compiler.MAX_TREE_FILES", 1):
                with self.assertRaisesRegex(CompilationError, "maximum of 1"):
                    check_tree(root)

    def test_tree_requires_unambiguous_relative_module_ids(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "a").mkdir()
            (root / "b").mkdir()
            (root / "a" / "foo.zmdl").write_text("value = true;", encoding="utf-8")
            (root / "b" / "foo.zmdl").write_text("value = true;", encoding="utf-8")
            structure = root / "structure.zstr"
            structure.write_text("(zmdl foo) = { };", encoding="utf-8")
            with self.assertRaisesRegex(CompilationError, "a/foo"):
                compile_tree(root, mode="interface")

            structure.write_text(
                "(zmdl a.foo) = { }; (zmdl b.foo) = { };",
                encoding="utf-8",
            )
            bundle = compile_tree(root, mode="interface")
            self.assertEqual(
                ["a/foo", "b/foo"],
                [item["module"] for item in bundle["structure"]["attachments"]],
            )

            structure.write_text(
                "(zmdl a.foo) = { }; (zmdl a.foo) = { };",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(CompilationError, "duplicate ZSTR attachment") as raised:
                compile_tree(root, mode="interface")
            self.assertIsNotNone(raised.exception.span)

    def test_tree_cli_writes_atomically_and_reports_json_success(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self._write_tree(root)
            output = root / "bundle.json"
            stdout = StringIO()
            self.assertEqual(
                0,
                main(
                    ["check-tree", "--root", str(root), "--diagnostic-format", "json"],
                    stdout,
                    StringIO(),
                ),
            )
            self.assertEqual({"diagnostics": []}, json.loads(stdout.getvalue()))
            self.assertEqual(
                0,
                main(
                    [
                        "compile-tree",
                        "--root",
                        str(root),
                        "--output",
                        str(output),
                        "--mode",
                        "interface",
                    ],
                    StringIO(),
                    StringIO(),
                ),
            )
            first = output.read_text(encoding="utf-8")
            self.assertEqual(compile_tree(root, mode="interface"), json.loads(first))

            output.write_text("previous\n", encoding="utf-8")
            with patch("zcfg.cli.os.replace", side_effect=OSError("replace failed")):
                status = main(
                    [
                        "compile-tree",
                        "--root",
                        str(root),
                        "--output",
                        str(output),
                    ],
                    StringIO(),
                    StringIO(),
                )
            self.assertEqual(1, status)
            self.assertEqual("previous\n", output.read_text(encoding="utf-8"))
            self.assertEqual([], list(root.glob(".bundle.json.*")))


if __name__ == "__main__":
    unittest.main()
