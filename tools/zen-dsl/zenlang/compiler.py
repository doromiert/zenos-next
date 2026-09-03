from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path, PurePath
from typing import Any

from .api import parse_file
from .emitter import NixEmitter, emit_attr_name, emit_nix_data, semantic_descriptor
from .model import (
    ActionStatement,
    Assignment,
    AttrSet,
    CallExpr,
    ConditionalStatement,
    Document,
    EnableOption,
    Expression,
    FileKind,
    GRAMMAR_VERSION,
    GroupExpr,
    IdentifierSegment,
    ImportStatement,
    ResolvedImport,
    IR_VERSION,
    LetStatement,
    ListExpr,
    Literal,
    StringExpr,
    StringSegment,
    StringText,
    StructuralMarker,
    Variable,
)


DESCRIPTOR_VERSION = "zenlang.semantic/1"
BUNDLE_VERSION = "zenlang.bundle/1"
MAX_TREE_FILES = 4096


class CompilationError(ValueError):
    """Raised when a valid AST needs semantics unavailable to a backend."""

    def __init__(self, message: str, span: Any | None = None):
        super().__init__(message)
        self.span = span


def compile_document(
    document: Document,
    *,
    mode: str = "build",
    target: str | None = None,
) -> str:
    if document.kind is FileKind.ZCFG:
        return compile_zcfg(document)
    if document.kind is FileKind.ZMDL:
        return compile_zmdl(document, target=target)
    if document.kind is FileKind.ZPKG:
        return compile_zpkg(document, mode=mode)
    if document.kind is FileKind.ZSTR:
        return compile_zstr(document)
    raise CompilationError(f"unsupported document kind: {document.kind!r}", document.span)


def document_descriptor(document: Document) -> dict[str, Any]:
    return {
        "descriptorVersion": DESCRIPTOR_VERSION,
        "grammarVersion": document.grammar_version,
        "irVersion": document.ir_version,
        "kind": document.kind.value,
        "statements": semantic_descriptor(_resolved_statements(document)),
    }


def check_tree(root: str | Path) -> dict[str, Document]:
    resolved_root = _tree_root(root)
    documents: dict[str, Document] = {}
    folded_paths: dict[str, str] = {}
    for relative, source in _discover_tree(resolved_root):
        folded = relative.casefold()
        previous = folded_paths.get(folded)
        if previous is not None:
            if previous == relative:
                message = f"duplicate source path: {relative}"
            else:
                message = f"case-colliding source paths: {previous} and {relative}"
            raise CompilationError(message)
        folded_paths[folded] = relative
        documents[relative] = parse_file(source, import_root=resolved_root)
    return documents


def compile_tree(root: str | Path, *, mode: str = "build") -> dict[str, Any]:
    if mode not in ("interface", "build"):
        raise CompilationError("ZPKG mode must be 'interface' or 'build'")
    resolved_root = _tree_root(root)
    documents = check_tree(resolved_root)
    sources = []
    structure = _tree_structure(documents)
    for relative, document in documents.items():
        target = None
        option_path = None
        if document.kind is FileKind.ZMDL:
            module_name = relative[: -len(".zmdl")]
            matches = [item for item in structure["attachments"] if item["module"] == module_name]
            if len(matches) != 1:
                raise CompilationError(
                    f"ZMDL module {module_name!r} requires exactly one ZSTR attachment",
                    document.span,
                )
            option_path = tuple(matches[0]["path"])
            if any(part.startswith("{") for part in option_path):
                raise CompilationError(
                    f"dynamic ZSTR attachment for {module_name!r} is not supported by this backend",
                    document.span,
                )
            target = matches[0]["target"]
            compiled = compile_zmdl(document, option_path=option_path, target=target)
        else:
            compiled = compile_document(document, mode=mode)
        sources.append(
            {
                "compiledNix": compiled,
                "descriptor": document_descriptor(document),
                "kind": document.kind.value,
                "path": relative,
            }
        )
    return {
        "bundleVersion": BUNDLE_VERSION,
        "grammarVersion": GRAMMAR_VERSION,
        "irVersion": IR_VERSION,
        "structure": structure,
        "sources": sources,
    }


def _tree_root(root: str | Path) -> Path:
    source = Path(root)
    try:
        resolved = source.resolve(strict=True)
        if not resolved.is_dir():
            raise OSError("path is not a directory")
        return resolved
    except (OSError, RuntimeError, ValueError) as error:
        raise CompilationError(f"cannot read source root {source}: {error}") from error


def _discover_tree(root: Path) -> list[tuple[str, Path]]:
    discovered: list[tuple[str, Path]] = []
    pending = [root]
    try:
        while pending:
            directory = pending.pop()
            with os.scandir(directory) as entries:
                for entry in entries:
                    if entry.is_dir(follow_symlinks=False):
                        pending.append(Path(entry.path))
                        continue
                    if Path(entry.name).suffix.lower() not in {
                        ".zcfg",
                        ".zmdl",
                        ".zpkg",
                        ".zstr",
                    }:
                        continue
                    relative = Path(entry.path).relative_to(root).as_posix()
                    discovered.append((relative, Path(entry.path)))
                    if len(discovered) > MAX_TREE_FILES:
                        raise CompilationError(
                            f"source file count exceeds the maximum of {MAX_TREE_FILES}"
                        )
    except CompilationError:
        raise
    except OSError as error:
        raise CompilationError(f"cannot scan source root {root}: {error}") from error
    discovered.sort(key=lambda item: item[0])
    return discovered


def compile_zcfg(document: Document) -> str:
    _require_kind(document, FileKind.ZCFG)
    emitter = NixEmitter()
    statements = _resolved_statements(document)
    emitted_statements = [
        statement
        for statement in statements
        if not isinstance(statement, (ResolvedImport, LetStatement))
    ]
    groups = _zcfg_groups(emitted_statements)
    root = next((tree for conditions, tree in groups if not conditions), {})
    conditional_groups = [
        (conditions, tree) for conditions, tree in groups if conditions
    ]
    bindings: list[str] = []
    for statement in statements:
        if isinstance(statement, (ResolvedImport, LetStatement)):
            bindings.append(emitter.statement(statement, 2))

    fragments = [_emit_tree(root, emitter, 2)]
    for conditions, tree in conditional_groups:
        condition = " && ".join(f"({emitter.expression(item)})" for item in conditions)
        if len(conditions) == 1:
            condition = emitter.expression(conditions[0])
        fragments.append(f"(lib.mkIf {condition} {_emit_tree(tree, emitter, 4)})")

    prefix = "{ pkgs, lib ? pkgs.lib, config ? { zenos = { }; }, maintainers ? lib.maintainers, licenses ? lib.licenses, ... }:\n"
    bindings.insert(0, f"name = {emit_nix_data(_source_name(document))};")
    if bindings:
        prefix += "let\n" + "\n".join(f"  {binding}" for binding in bindings) + "\nin\n"
    if len(fragments) == 1:
        return prefix + fragments[0] + "\n"
    return (
        prefix
        + "lib.mkMerge [\n"
        + "\n".join(f"  {fragment}" for fragment in fragments)
        + "\n]\n"
    )


def compile_zmdl(
    document: Document,
    *,
    option_path: tuple[str, ...] | None = None,
    target: str | None = None,
) -> str:
    _require_kind(document, FileKind.ZMDL)
    if target not in ("system", "user"):
        raise CompilationError("ZMDL compilation requires target='system' or target='user'", document.span)
    module_path = option_path or (_source_name(document),)
    emitter = NixEmitter({"path": "cfg"})
    top_metadata: dict[str, Expression] = {}
    option_lines: list[tuple[tuple[str, ...], str]] = []
    actions: list[str] = []
    bindings: list[str] = []
    aliases: list[dict[str, Any]] = []

    for statement in _resolved_statements(document):
        if isinstance(statement, ResolvedImport):
            bindings.append(emitter.statement(statement, 2))
            continue
        if isinstance(statement, ImportStatement):
            raise CompilationError("filesystem import was not resolved with parse_file", statement.span)
        if isinstance(statement, LetStatement):
            bindings.append(emitter.statement(statement, 2))
            continue
        if not isinstance(statement, Assignment):
            raise CompilationError(
                f"unsupported top-level ZMDL statement: {type(statement).__name__}",
                statement.span,
            )
        path = _assignment_path(statement)
        if path and path[0] == "_meta":
            _collect_metadata(top_metadata, path[1:], statement.value)
            continue
        if isinstance(statement.target, StructuralMarker):
            if statement.target.kind == "freeform":
                freeform_path = _static_path(statement.target.argument)
                option_lines.append(
                    (freeform_path, _freeform_option(statement.value))
                )
                actions.extend(
                    _freeform_actions(statement.value, freeform_path, emitter, target=target)
                )
                continue
            if statement.target.kind == "alias":
                aliases.append(
                    {
                        "path": semantic_descriptor(statement.target.argument),
                        "value": semantic_descriptor(statement.value),
                    }
                )
                continue
            raise CompilationError(
                f"unsupported ZMDL structural marker: {statement.target.kind}",
                statement.target.span,
            )
        option_lines.append((path, _option_declaration(statement.value, emitter)))
        actions.extend(_option_actions(statement.value, path, emitter, target=target))

    option_lines.sort(key=lambda item: item[0])
    option_padding = " " * 4
    options_body = "{ }"
    if option_lines:
        options_body = (
            "{\n"
            + "\n".join(
                f"{option_padding}{_emit_static_path(path)} = {value};"
                for path, value in option_lines
            )
            + "\n  }"
        )

    descriptor = {
        "descriptorVersion": DESCRIPTOR_VERSION,
        "grammarVersion": document.grammar_version,
        "irVersion": document.ir_version,
        "kind": "zmdl",
        "metadata": {
            key: semantic_descriptor(value)
            for key, value in sorted(top_metadata.items())
        },
        "modulePath": list(module_path),
        "compileTarget": target,
        "aliases": aliases,
        "statements": semantic_descriptor(_resolved_statements(document)),
    }
    metadata_fragment = (
        "{ _module.args.zenlang.descriptors."
        + _emit_static_path(module_path)
        + " = "
        + emit_nix_data(descriptor, 2)
        + "; }"
    )
    config_fragments = [metadata_fragment, *actions]
    config_value = (
        config_fragments[0]
        if len(config_fragments) == 1
        else "lib.mkMerge [\n"
        + "\n".join(f"    {fragment}" for fragment in config_fragments)
        + "\n  ]"
    )

    module_lines = []
    module_lines.append(
        f"  options.{_emit_static_path(('zenos', *module_path))} = {options_body};"
    )
    module_lines.append(f"  config = {config_value};")

    output = "{ config, lib, pkgs, maintainers ? lib.maintainers, licenses ? lib.licenses, ... }:\nlet\n"
    output += f"  cfg = config.{_emit_static_path(('zenos', *module_path))};\n"
    output += f"  name = {emit_nix_data(_source_name(document))};\n"
    if bindings:
        output += "\n".join(f"  {binding}" for binding in bindings) + "\n"
    output += "in\n{\n" + "\n".join(module_lines) + "\n}\n"
    return output


def compile_zpkg(document: Document, *, mode: str = "build") -> str:
    _require_kind(document, FileKind.ZPKG)
    if mode not in ("interface", "build"):
        raise CompilationError("ZPKG mode must be 'interface' or 'build'", document.span)
    emitter = NixEmitter({"src": "src", "type": "types"})
    metadata: dict[str, Expression] = {}
    fields: dict[tuple[str, ...], Expression] = {}
    dependency_ops: dict[str, list[tuple[str, Expression]]] = {
        "global": [],
        "build": [],
        "run": [],
        "export": [],
    }
    local_bindings: list[ResolvedImport | LetStatement] = []

    for statement in _resolved_statements(document):
        if isinstance(statement, ResolvedImport):
            local_bindings.append(statement)
            continue
        if isinstance(statement, ImportStatement):
            raise CompilationError("filesystem import was not resolved with parse_file", statement.span)
        if isinstance(statement, LetStatement):
            local_bindings.append(statement)
            continue
        if not isinstance(statement, Assignment):
            raise CompilationError(
                f"unsupported top-level ZPKG statement: {type(statement).__name__}",
                statement.span,
            )
        path = _assignment_path(statement)
        if path == ("_meta", "deps") and isinstance(statement.value, AttrSet):
            _collect_dependency_ops(dependency_ops, statement.value)
        elif path and path[0] == "_meta":
            _collect_metadata(metadata, path[1:], statement.value)
        else:
            if path in fields and type(fields[path]) is not type(statement.value):
                raise CompilationError(f"incompatible duplicate field: {'.'.join(path)}", statement.span)
            fields[path] = statement.value

    dependency_metadata = metadata.pop("deps", None)
    if dependency_metadata is not None:
        if not isinstance(dependency_metadata, AttrSet):
            raise CompilationError("_meta.deps must be an attribute set", dependency_metadata.span)
        _collect_dependency_ops(dependency_ops, dependency_metadata)

    global_dependencies = _apply_dependency_ops((), dependency_ops["global"])
    build_dependencies = _apply_dependency_ops(global_dependencies, dependency_ops["build"])
    run_dependencies = _apply_dependency_ops(global_dependencies, dependency_ops["run"])
    export_dependencies = _apply_dependency_ops(global_dependencies, dependency_ops["export"])
    _check_dependency_short_names(
        (*global_dependencies, *build_dependencies, *run_dependencies, *export_dependencies)
    )
    import_data = [
        semantic_descriptor(statement)
        for statement in local_bindings
        if isinstance(statement, ResolvedImport)
    ]
    if mode == "interface":
        descriptor = {
            "descriptorVersion": DESCRIPTOR_VERSION,
            "grammarVersion": document.grammar_version,
            "irVersion": document.ir_version,
            "kind": "zpkg",
            "name": _source_name(document),
            "metadata": {
                key: semantic_descriptor(value)
                for key, value in sorted(metadata.items())
            },
            "dependencies": {
                "global": _dependency_descriptors(global_dependencies),
                "build": _dependency_descriptors(build_dependencies),
                "run": _dependency_descriptors(run_dependencies),
                "export": _dependency_descriptors(export_dependencies),
            },
            "fields": [
                {
                    "path": list(path),
                    "value": semantic_descriptor(value),
                }
                for path, value in sorted(fields.items())
            ],
            "imports": import_data,
            "statements": semantic_descriptor(_resolved_statements(document)),
        }
        return "{ ... }:\n" + emit_nix_data(descriptor) + "\n"

    global_expression = _emit_dependencies(global_dependencies)
    build_expression = _emit_dependencies(build_dependencies)
    run_expression = _emit_dependencies(run_dependencies)
    export_expression = _emit_dependencies(export_dependencies)

    bindings: list[str] = [
        f"globalDependencies = {global_expression};",
        f"buildDependencies = {build_expression};",
        f"runDependencies = {run_expression};",
        f"exportDependencies = {export_expression};",
        "dependencySets = { global = globalDependencies; build = buildDependencies; run = runDependencies; export = exportDependencies; };",
        "deps = if zenRuntime == null then { } else zenRuntime.resolveDependencies dependencySets;",
        "src = if zenRuntime == null then { } else zenRuntime.src;",
        "types = if zenRuntime == null then { } else zenRuntime.types;",
    ]
    bindings.extend(emitter.statement(statement) for statement in local_bindings)

    metadata_lines = [
        f"    {emit_attr_name(key)} = {emitter.expression(value, 4)};"
        for key, value in sorted(metadata.items())
    ]
    metadata_text = (
        "{ }" if not metadata_lines else "{\n" + "\n".join(metadata_lines) + "\n  }"
    )
    field_lines = [
        f"    {_emit_static_path(key)} = {emitter.expression(value, 4)};"
        for key, value in sorted(fields.items())
    ]
    fields_text = "{ }" if not field_lines else "{\n" + "\n".join(field_lines) + "\n  }"
    bindings.append(
        "descriptor = {\n"
        f'    descriptorVersion = "{DESCRIPTOR_VERSION}";\n'
        f"    grammarVersion = {emit_nix_data(document.grammar_version)};\n"
        f"    irVersion = {emit_nix_data(document.ir_version)};\n"
        '    kind = "zpkg";\n'
        f"    name = {emit_nix_data(_source_name(document))};\n"
        f"    metadata = {metadata_text};\n"
        "    dependencies = dependencySets;\n"
        f"    fields = {fields_text};\n"
        f"    imports = {emit_nix_data(import_data, 4)};\n"
        f"    statements = {emit_nix_data(semantic_descriptor(_resolved_statements(document)), 4)};\n"
        "  };"
    )

    output = "{ lib, pkgs ? { zenos = { }; }, zenRuntime ? null, zenosVersion ? null, maintainers ? lib.maintainers, licenses ? lib.licenses, ... }:\nlet\n"
    bindings.insert(0, f"name = {emit_nix_data(_source_name(document))};")
    output += "\n".join(f"  {binding}" for binding in bindings) + "\nin\n"
    minimum = metadata.get("minVersion") or metadata.get("zenosVersion")
    if minimum is not None:
        required = emitter.expression(minimum)
        output += "assert zenosVersion != null;\n"
        output += f"assert lib.versionAtLeast zenosVersion {required};\n"
    output += "assert zenRuntime != null;\n"
    return output + "zenRuntime.buildPackage descriptor\n"


def compile_zstr(document: Document) -> str:
    _require_kind(document, FileKind.ZSTR)
    descriptor = {
        "descriptorVersion": DESCRIPTOR_VERSION,
        "grammarVersion": document.grammar_version,
        "irVersion": document.ir_version,
        "kind": "zstr",
        "statements": semantic_descriptor(_resolved_statements(document)),
    }
    return emit_nix_data(descriptor) + "\n"


def _require_kind(document: Document, expected: FileKind) -> None:
    if document.kind is not expected:
        raise CompilationError(
            f"expected {expected.value.upper()} document, got {document.kind.value.upper()}",
            document.span,
        )


def _source_name(document: Document) -> str:
    name = PurePath(document.span.source).name
    suffix = "." + document.kind.value
    return name[: -len(suffix)] if name.lower().endswith(suffix) else name


def _assignment_path(statement: Assignment) -> tuple[str, ...]:
    if isinstance(statement.target, StructuralMarker):
        return ()
    return _static_path(statement.target)


def _static_path(segments: Any, span: Any | None = None) -> tuple[str, ...]:
    values: list[str] = []
    for segment in segments or ():
        if isinstance(segment, IdentifierSegment):
            values.append(segment.name)
        elif isinstance(segment, StringSegment):
            values.append(segment.value)
        else:
            raise CompilationError(
                "dynamic attribute paths require a runtime descriptor",
                span or segment.span,
            )
    if not values:
        raise CompilationError("attribute path cannot be empty", span)
    return tuple(values)


def _resolved_statements(document: Document) -> tuple[Any, ...]:
    imported: list[Any] = []
    local: list[Any] = []
    for statement in document.statements:
        if isinstance(statement, ImportStatement):
            raise CompilationError(
                "filesystem import was not resolved with parse_file",
                statement.span,
            )
        if isinstance(statement, ResolvedImport) and statement.binding is None:
            imported.extend(_resolved_statements(statement.document))
        else:
            local.append(statement)
    effective = _coalesce_assignments(tuple((*imported, *local)))
    bindings: dict[str, Any] = {}
    for statement in effective:
        name = None
        if isinstance(statement, LetStatement):
            name = statement.name
        elif isinstance(statement, ResolvedImport):
            name = statement.binding
        if name is None:
            continue
        if name in bindings:
            raise CompilationError(
                f"imported lexical binding {name!r} collides with another declaration",
                statement.span,
            )
        bindings[name] = statement
    return effective


def _coalesce_assignments(statements: tuple[Any, ...]) -> tuple[Any, ...]:
    if any(
        isinstance(statement, Assignment) and statement.operator != "="
        for statement in statements
    ):
        return statements
    result: list[Any] = []
    positions: dict[str, int] = {}
    for statement in statements:
        if not isinstance(statement, Assignment) or statement.operator != "=":
            result.append(statement)
            continue
        key = repr(semantic_descriptor(statement.target))
        previous_index = positions.get(key)
        if previous_index is None:
            positions[key] = len(result)
            result.append(statement)
            continue
        previous = result[previous_index]
        if isinstance(previous.value, AttrSet) and isinstance(statement.value, AttrSet):
            merged_value = AttrSet(
                _coalesce_assignments((*previous.value.statements, *statement.value.statements)),
                previous.value.recursive or statement.value.recursive,
                statement.value.span,
            )
            result[previous_index] = Assignment(
                statement.target,
                statement.operator,
                merged_value,
                statement.span,
            )
        elif _compatible_assignment_values(previous.value, statement.value):
            result[previous_index] = statement
        else:
            raise CompilationError(
                "incompatible duplicate assignment",
                statement.span,
            )
    return tuple(result)


def _tree_structure(documents: dict[str, Document]) -> dict[str, Any]:
    attachments: list[dict[str, Any]] = []
    aliases: list[dict[str, Any]] = []

    def marker_path(marker: StructuralMarker) -> tuple[str, ...]:
        return _static_path(marker.argument, marker.span)

    def visit(statements: tuple[Any, ...], prefix: tuple[str, ...]) -> None:
        for statement in statements:
            if isinstance(statement, ResolvedImport) and statement.binding is None:
                continue
            if not isinstance(statement, Assignment):
                continue
            if isinstance(statement.target, StructuralMarker):
                nested_prefix = prefix
                if statement.target.kind == "zmdl":
                    module = marker_path(statement.target)
                    path = (*prefix, *module)
                    nested_prefix = path
                    attachments.append(
                        {
                            "module": "/".join(module),
                            "path": list(path),
                            "target": "user" if path and path[0] == "users" else "system",
                            "_span": statement.target.span,
                        }
                    )
                elif statement.target.kind == "alias":
                    aliases.append(
                        {
                            "path": list((*prefix, *marker_path(statement.target))),
                            "value": semantic_descriptor(statement.value),
                        }
                    )
                elif statement.target.kind == "freeform":
                    freeform = marker_path(statement.target)
                    nested_prefix = (*prefix, "{" + freeform[-1] + "}")
                if isinstance(statement.value, AttrSet):
                    visit(statement.value.statements, nested_prefix)
                continue
            path = (*prefix, *_assignment_path(statement))
            if isinstance(statement.value, StructuralMarker):
                marker = statement.value
                owner = path[:-2] if path[-2:] == ("_meta", "type") else path
                if marker.kind == "zmdl":
                    module = marker_path(marker)
                    attachments.append(
                        {
                            "module": "/".join(module),
                            "path": list(owner),
                            "target": "user" if owner and owner[0] == "users" else "system",
                            "_span": marker.span,
                        }
                    )
                elif marker.kind == "alias":
                    aliases.append(
                        {
                            "path": list(owner),
                            "value": {"marker": semantic_descriptor(marker)},
                        }
                    )
            elif isinstance(statement.value, AttrSet):
                visit(statement.value.statements, path)

    for _relative, document in documents.items():
        if document.kind is FileKind.ZSTR:
            visit(document.statements, ())
    modules: dict[str, dict[str, Any]] = {}
    paths: dict[tuple[str, ...], dict[str, Any]] = {}
    for attachment in attachments:
        previous_module = modules.get(attachment["module"])
        if previous_module is not None:
            raise CompilationError(
                f"duplicate ZSTR attachment for module {attachment['module']!r}",
                attachment["_span"],
            )
        path_key = tuple(attachment["path"])
        previous_path = paths.get(path_key)
        if previous_path is not None:
            raise CompilationError(
                f"ZSTR attachment path {'.'.join(path_key)!r} is already used by {previous_path['module']!r}",
                attachment["_span"],
            )
        modules[attachment["module"]] = attachment
        paths[path_key] = attachment
    attachments.sort(key=lambda item: (item["module"], item["path"]))
    for attachment in attachments:
        del attachment["_span"]
    aliases.sort(key=lambda item: item["path"])
    return {"aliases": aliases, "attachments": attachments}


def _emit_static_path(path: tuple[str, ...]) -> str:
    return ".".join(emit_attr_name(part) for part in path)


def _zcfg_groups(
    statements: list[Any],
) -> list[tuple[tuple[Expression, ...], dict[str, Any]]]:
    groups: list[tuple[tuple[Expression, ...], dict[str, Any]]] = []

    def tree_for(conditions: tuple[Expression, ...]) -> dict[str, Any]:
        for existing_conditions, tree in groups:
            if existing_conditions == conditions:
                return tree
        tree: dict[str, Any] = {}
        groups.append((conditions, tree))
        return tree

    def visit(
        current: tuple[Any, ...],
        prefix: tuple[str, ...],
        conditions: tuple[Expression, ...],
        *,
        route_root: bool,
        forbid_zenos: bool = False,
    ) -> None:
        for statement in current:
            if isinstance(statement, ConditionalStatement):
                visit(
                    statement.body.statements,
                    prefix,
                    (*conditions, statement.condition),
                    route_root=route_root,
                    forbid_zenos=forbid_zenos,
                )
                continue
            if not isinstance(statement, Assignment) or statement.operator != "=":
                raise CompilationError(
                    "ZCFG output supports assignments, conditionals, and top-level bindings",
                    statement.span,
                )
            path = _assignment_path(statement)
            child_forbid_zenos = forbid_zenos
            if route_root and path[0] == "legacy":
                path = path[1:]
                child_forbid_zenos = True
                if not path and not isinstance(statement.value, AttrSet):
                    raise CompilationError("legacy must be an attribute set", statement.span)
            elif route_root:
                path = ("zenos", *path)
            else:
                path = (*prefix, *path)
            if child_forbid_zenos and path and path[0] == "zenos":
                raise CompilationError("legacy cannot contain the zenos option tree", statement.span)
            if isinstance(statement.value, AttrSet):
                if not statement.value.statements:
                    if path:
                        _insert_tree(tree_for(conditions), path, {}, statement.span)
                    continue
                visit(
                    statement.value.statements,
                    path,
                    conditions,
                    route_root=False,
                    forbid_zenos=child_forbid_zenos,
                )
            else:
                if not path:
                    raise CompilationError("legacy must be an attribute set", statement.span)
                _insert_tree(tree_for(conditions), path, statement.value, statement.span)

    visit(tuple(statements), (), (), route_root=True)
    return groups


def _insert_tree(
    tree: dict[str, Any], path: tuple[str, ...], value: Any, span: Any | None = None
) -> None:
    if not path:
        raise CompilationError("cannot assign an empty path")
    current = tree
    for segment in path[:-1]:
        existing = current.get(segment)
        if existing is None:
            child: dict[str, Any] = {}
            current[segment] = child
            current = child
        elif isinstance(existing, dict):
            current = existing
        else:
            raise CompilationError(f"conflicting assignment at {'.'.join(path)}", span)
    leaf = path[-1]
    if leaf in current:
        existing = current[leaf]
        if isinstance(existing, dict) and isinstance(value, dict):
            _merge_tree(existing, value)
            return
        if _compatible_assignment_values(existing, value):
            current[leaf] = value
            return
        raise CompilationError(f"incompatible assignment at {'.'.join(path)}", span)
    current[leaf] = value


def _merge_tree(left: dict[str, Any], right: dict[str, Any]) -> None:
    for key, value in right.items():
        if key in left and isinstance(left[key], dict) and isinstance(value, dict):
            _merge_tree(left[key], value)
        elif key in left:
            raise CompilationError(f"conflicting assignment at {key}")
        else:
            left[key] = value


def _compatible_assignment_values(left: Any, right: Any) -> bool:
    if type(left) is not type(right):
        return False
    if isinstance(left, Literal):
        return left.kind == right.kind
    return True


def _emit_tree(tree: dict[str, Any], emitter: NixEmitter, indent: int) -> str:
    if not tree:
        return "{ }"
    padding = " " * (indent + 2)
    lines: list[str] = []
    for key in sorted(tree):
        value = tree[key]
        if isinstance(value, dict):
            emitted = _emit_tree(value, emitter, indent + 2)
        else:
            emitted = emitter.expression(value, indent + 2)
        lines.append(f"{padding}{emit_attr_name(key)} = {emitted};")
    return "{\n" + "\n".join(lines) + "\n" + " " * indent + "}"


def _collect_metadata(
    result: dict[str, Expression], path: tuple[str, ...], value: Expression
) -> None:
    if not path:
        if not isinstance(value, AttrSet):
            raise CompilationError("_meta must be an attribute set", value.span)
        for statement in value.statements:
            if not isinstance(statement, Assignment):
                raise CompilationError("metadata may contain only assignments", statement.span)
            child_path = _assignment_path(statement)
            _collect_metadata(result, child_path, statement.value)
        return
    if len(path) != 1:
        raise CompilationError(
            "nested metadata values are not supported by this backend",
            value.span,
        )
    if path[0] in result:
        raise CompilationError(f"duplicate metadata field: {path[0]}", value.span)
    result[path[0]] = value


def _option_parts(
    value: Expression,
) -> tuple[dict[str, Expression], list[ActionStatement], bool]:
    enabled = isinstance(value, EnableOption)
    body = (
        value.body
        if isinstance(value, EnableOption)
        else value
        if isinstance(value, AttrSet)
        else None
    )
    metadata: dict[str, Expression] = {}
    actions: list[ActionStatement] = []
    if body is not None:
        for statement in body.statements:
            if isinstance(statement, ActionStatement):
                actions.append(statement)
            elif isinstance(statement, Assignment):
                path = _assignment_path(statement)
                if path and path[0] == "_meta":
                    _collect_metadata(metadata, path[1:], statement.value)
    return metadata, actions, enabled


def _option_declaration(value: Expression, emitter: NixEmitter) -> str:
    metadata, _, enabled = _option_parts(value)
    option_type = (
        "lib.types.bool"
        if enabled
        else _option_type(metadata.get("type"), value, emitter)
    )
    default = metadata.get("default")
    if default is None and enabled:
        default_text = "false"
    elif default is None and not isinstance(value, (AttrSet, EnableOption)):
        default_text = emitter.expression(value)
    else:
        default_text = emitter.expression(default) if default is not None else None
    fields = [f"type = {option_type};"]
    if default_text is not None:
        fields.append(f"default = {default_text};")
    description = metadata.get("description") or metadata.get("brief")
    if description is not None:
        fields.append(f"description = {emitter.expression(description)};")
    if "example" in metadata:
        fields.append(f"example = {emitter.expression(metadata['example'])};")
    return "lib.mkOption { " + " ".join(fields) + " }"


def _freeform_option(value: Expression) -> str:
    _option_parts(value)
    fields = ["type = lib.types.attrsOf lib.types.anything;", "default = { };"]
    return "lib.mkOption { " + " ".join(fields) + " }"


def _option_type(
    annotation: Expression | None, value: Expression, emitter: NixEmitter
) -> str:
    if annotation is not None:
        return _emit_type(annotation, emitter)
    if isinstance(value, Literal):
        return {
            "true": "lib.types.bool",
            "false": "lib.types.bool",
            "integer": "lib.types.int",
            "float": "lib.types.float",
        }.get(
            value.kind,
            "lib.types.str" if isinstance(value.value, str) else "lib.types.anything",
        )
    if isinstance(value, StringExpr):
        return "lib.types.str"
    if isinstance(value, ListExpr):
        return "lib.types.listOf lib.types.anything"
    if isinstance(value, AttrSet):
        return "lib.types.attrs"
    return "lib.types.anything"


def _emit_type(annotation: Expression, emitter: NixEmitter) -> str:
    if isinstance(annotation, GroupExpr):
        return _emit_type(annotation.value, emitter)
    aliases = {
        "string": "str",
        "boolean": "bool",
        "set": "attrsOf",
        "list": "listOf",
    }
    if (
        isinstance(annotation, Variable)
        and annotation.name == "type"
        and len(annotation.path) == 1
    ):
        name = _static_path(annotation.path)[0]
        if name == "null":
            return "(lib.types.enum [ null ])"
        return "lib.types." + aliases.get(name, name)
    if isinstance(annotation, CallExpr) and isinstance(annotation.callee, Variable):
        callee = annotation.callee
        if callee.name == "type" and len(callee.path) == 1:
            name = _static_path(callee.path)[0]
            argument = annotation.arguments[0] if annotation.arguments else None
            if (
                name in ("list", "set", "functionTo")
                and isinstance(argument, ListExpr)
                and len(argument.items) == 1
            ):
                function = {
                    "list": "listOf",
                    "set": "attrsOf",
                    "functionTo": "functionTo",
                }[name]
                return (
                    f"(lib.types.{function} {_emit_type(argument.items[0], emitter)})"
                )
            if name == "enum" and isinstance(argument, ListExpr):
                return f"(lib.types.enum {emitter.expression(argument)})"
            if name == "either" and isinstance(argument, ListExpr):
                types = [_emit_type(item, emitter) for item in argument.items]
                result = types[-1]
                for item in reversed(types[:-1]):
                    result = f"(lib.types.either {item} {result})"
                return result
    return emitter.expression(annotation)


def _option_actions(
    value: Expression,
    path: tuple[str, ...],
    emitter: NixEmitter,
    *,
    target: str,
) -> list[str]:
    _, actions, _ = _option_parts(value)
    option_value = "cfg." + _emit_static_path(path)
    return [
        _emit_action(action, emitter, conditional_base=option_value, target=target)
        for action in actions
    ]


def _freeform_actions(
    value: Expression,
    path: tuple[str, ...],
    emitter: NixEmitter,
    *,
    target: str,
) -> list[str]:
    _, actions, _ = _option_parts(value)
    if not actions:
        return []
    variable = path[-1]
    local_emitter = NixEmitter({"f": None, "path": "cfg"})
    rendered = [
        _emit_action(action, local_emitter, conditional_base="true", target=target)
        for action in actions
    ]
    body = (
        rendered[0]
        if len(rendered) == 1
        else "lib.mkMerge [ " + " ".join(rendered) + " ]"
    )
    return [
        "(lib.mkMerge (lib.mapAttrsToList "
        f"({local_emitter.binding_name(variable)}: _zenValue: {body}) "
        f"cfg.{_emit_static_path(path)}))"
    ]


def _emit_action(
    action: ActionStatement,
    emitter: NixEmitter,
    *,
    conditional_base: str,
    target: str,
) -> str:
    body = emitter.attr_set(action.body, 4)
    if action.scope == "system":
        routed = body
    elif action.scope == "user":
        routed = "{ home-manager.sharedModules = [ " + body + " ]; }"
    elif action.scope == "shared":
        routed = (
            body
            if target == "system"
            else "{ home-manager.sharedModules = [ " + body + " ]; }"
        )
    else:
        raise CompilationError(f"unknown action scope: {action.scope!r}", action.span)
    if action.unconditional:
        return routed
    condition = emitter.guard_condition(action.guards, conditional_base)
    return f"(lib.mkIf ({condition}) {routed})"


def _collect_dependency_ops(
    result: dict[str, list[tuple[str, Expression]]], body: AttrSet
) -> None:
    for statement in body.statements:
        if not isinstance(statement, Assignment):
            raise CompilationError("dependency sets may contain only assignments", statement.span)
        path = _assignment_path(statement)
        if len(path) != 1 or path[0] not in result:
            raise CompilationError(
                "dependency scopes must be global, build, run, or export",
                statement.span,
            )
        result[path[0]].append((statement.operator, statement.value))


@dataclass(frozen=True)
class _Dependency:
    identity: tuple[str, ...]
    min_version: str | None
    span: Any


def _apply_dependency_ops(
    initial: tuple[_Dependency, ...],
    operations: list[tuple[str, Expression]],
) -> tuple[_Dependency, ...]:
    result = list(initial)
    for operator, value in operations:
        if not isinstance(value, ListExpr):
            raise CompilationError("dependency cascade operations require list values", value.span)
        dependencies = [_dependency(item) for item in value.items]
        if operator == "=":
            result = []
            for dependency in dependencies:
                _append_dependency(result, dependency)
        elif operator == "++":
            for dependency in dependencies:
                _append_dependency(result, dependency)
        elif operator == "--":
            for dependency in dependencies:
                index = next(
                    (index for index, existing in enumerate(result) if existing.identity == dependency.identity),
                    None,
                )
                if index is None:
                    raise CompilationError(
                        "cannot remove absent dependency " + ".".join(("$pkgs", *dependency.identity)),
                        dependency.span,
                    )
                result.pop(index)
        else:
            raise CompilationError(f"unknown dependency cascade operator: {operator!r}", value.span)
    return tuple(result)


def _append_dependency(result: list[_Dependency], dependency: _Dependency) -> None:
    existing = next((item for item in result if item.identity == dependency.identity), None)
    if existing is None:
        result.append(dependency)
        return
    if existing.min_version != dependency.min_version:
        raise CompilationError(
            "conflicting duplicate dependency " + ".".join(("$pkgs", *dependency.identity)),
            dependency.span,
        )


def _dependency(expression: Expression) -> _Dependency:
    candidate = expression.value if isinstance(expression, GroupExpr) else expression
    if isinstance(candidate, Variable):
        identity = _canonical_package_identity(candidate)
        return _Dependency(identity, None, expression.span)
    if isinstance(candidate, AttrSet):
        fields: dict[str, Expression] = {}
        for statement in candidate.statements:
            if not isinstance(statement, Assignment) or statement.operator != "=":
                raise CompilationError("dependency records contain only assignments", statement.span)
            path = _assignment_path(statement)
            if len(path) != 1 or path[0] in fields or path[0] not in ("id", "minVersion"):
                raise CompilationError("dependency records support only id and minVersion", statement.span)
            fields[path[0]] = statement.value
        if "id" not in fields or not isinstance(fields["id"], Variable):
            raise CompilationError("dependency records require a canonical id", candidate.span)
        identity = _canonical_package_identity(fields["id"])
        minimum = fields.get("minVersion")
        min_version = None
        if minimum is not None:
            if not isinstance(minimum, StringExpr) or any(not isinstance(part, StringText) for part in minimum.parts):
                raise CompilationError("dependency minVersion must be a plain string", minimum.span)
            min_version = "".join(part.value for part in minimum.parts)
        return _Dependency(identity, min_version, expression.span)
    raise CompilationError("invalid dependency record", expression.span)


def _canonical_package_identity(variable: Variable) -> tuple[str, ...]:
    if variable.name != "pkgs" or len(variable.path) < 2:
        raise CompilationError("dependency IDs must use $pkgs.zenos.<path>", variable.span)
    identity = _static_path(variable.path, variable.span)
    if identity[0] != "zenos":
        raise CompilationError("dependency IDs must use $pkgs.zenos.<path>", variable.span)
    return identity


def _check_dependency_short_names(dependencies: tuple[_Dependency, ...]) -> None:
    names: dict[str, tuple[str, ...]] = {}
    for dependency in dependencies:
        short = dependency.identity[-1]
        previous = names.get(short)
        if previous is not None and previous != dependency.identity:
            raise CompilationError(
                f"dependency short name {short!r} collides between "
                f"{'.'.join(previous)} and {'.'.join(dependency.identity)}",
                dependency.span,
            )
        names[short] = dependency.identity


def _emit_dependencies(dependencies: tuple[_Dependency, ...]) -> str:
    if not dependencies:
        return "[ ]"
    records = []
    for dependency in dependencies:
        identity = "pkgs." + ".".join(emit_attr_name(part) for part in dependency.identity)
        minimum = "null" if dependency.min_version is None else emit_nix_data(dependency.min_version)
        records.append(f"{{ id = {identity}; minVersion = {minimum}; }}")
    return "[ " + " ".join(records) + " ]"


def _dependency_descriptors(dependencies: tuple[_Dependency, ...]) -> list[dict[str, Any]]:
    return [
        {
            "id": "$pkgs." + ".".join(dependency.identity),
            "minVersion": dependency.min_version,
        }
        for dependency in dependencies
    ]
