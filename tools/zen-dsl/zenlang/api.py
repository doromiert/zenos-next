from __future__ import annotations

import os
from pathlib import Path
import stat
from typing import Any

from .lexer import Token, lex
from .model import (
    Diagnostic,
    Document,
    FileKind,
    ImportStatement,
    Interpolation,
    Span,
    ResolvedImport,
    StringExpr,
    StringText,
    ZenLangError,
)
from .parser import parse_tokens
from .validation import validate, validate_import_merges


_MAX_IMPORT_DEPTH = 256
_MAX_SOURCE_BYTES = 4 * 1024 * 1024
_MAX_IMPORTS = 1024
_MAX_TOTAL_SOURCE_BYTES = 32 * 1024 * 1024


def parse(text: str, source: str, *, validate_semantics: bool = True) -> Document:
    kind = FileKind.from_source(source)
    document = parse_tokens(lex(text, source), kind)
    if validate_semantics:
        validate(document)
    return document


def parse_file(
    path: str | Path,
    *,
    validate_semantics: bool = True,
    import_root: str | Path | None = None,
) -> Document:
    entry = Path(path)
    source = str(entry)
    sources: dict[str, str] = {}
    try:
        boundary_path = Path(import_root) if import_root is not None else entry.parent
        boundary = _resolve_path(
            boundary_path,
            str(boundary_path),
            code="ZEN301",
            message="cannot resolve import root",
            span=Span.point(source),
        )
        resolved_entry = _resolve_path(
            entry,
            source,
            code="ZEN301",
            message="cannot resolve source file",
            span=Span.point(source),
        )
        _require_within_root(
            resolved_entry,
            boundary,
            Span.point(source),
            subject="source file",
        )
        resolver = _ImportResolver(
            boundary,
            validate_semantics=validate_semantics,
            sources=sources,
        )
        return resolver.load(resolved_entry, source, Span.point(source), imported=False)
    except ZenLangError as error:
        error.sources.update(sources)
        raise


class _ImportResolver:
    def __init__(
        self,
        root: Path,
        *,
        validate_semantics: bool,
        sources: dict[str, str],
    ):
        self.root = root
        self.validate_semantics = validate_semantics
        self.sources = sources
        self.cache: dict[Path, Document] = {}
        self.stack: list[Path] = []
        self.import_count = 0
        self.total_source_bytes = 0

    def load(
        self,
        path: Path,
        label: str,
        span: Span,
        *,
        imported: bool,
    ) -> Document:
        if path in self.stack:
            cycle = (*self.stack, path)
            raise ZenLangError(
                Diagnostic(
                    "ZEN305",
                    "import cycle detected",
                    span,
                    notes=("import trace: " + " -> ".join(str(item) for item in cycle),),
                )
            )
        cached = self.cache.get(path)
        if cached is not None:
            return cached
        if len(self.stack) > _MAX_IMPORT_DEPTH:
            raise ZenLangError(
                Diagnostic(
                    "ZEN307",
                    f"import depth exceeds the maximum of {_MAX_IMPORT_DEPTH}",
                    span,
                    notes=("import trace: " + " -> ".join(str(item) for item in self.stack),),
                )
            )
        text, source_bytes = _read_source(
            path,
            label,
            span,
            imported=imported,
            remaining_total_bytes=_MAX_TOTAL_SOURCE_BYTES - self.total_source_bytes,
            root=self.root,
        )
        self.total_source_bytes += source_bytes
        self.sources[label] = text
        document = parse(text, label, validate_semantics=False)
        self.stack.append(path)
        try:
            bare: list[ResolvedImport] = []
            local: list[Any] = []
            diagnostics = list(document.diagnostics)
            for statement in document.statements:
                if not isinstance(statement, ImportStatement):
                    local.append(statement)
                    continue
                child = self._load_import(path, document.kind, statement)
                resolved = ResolvedImport(
                    child,
                    statement.binding,
                    statement.annotation,
                    statement.span,
                )
                if statement.binding is None:
                    bare.append(resolved)
                else:
                    local.append(resolved)
                diagnostics.extend(child.diagnostics)
            result = Document(
                document.kind,
                document.grammar_version,
                document.ir_version,
                tuple((*bare, *local)),
                document.span,
                tuple(dict.fromkeys(diagnostics)),
            )
            if self.validate_semantics:
                validate(result)
                validate_import_merges(result)
            self.cache[path] = result
            return result
        finally:
            self.stack.pop()

    def _load_import(
        self,
        current_path: Path,
        kind: FileKind,
        statement: ImportStatement,
    ) -> Document:
        relative = _import_path(statement)
        if not relative:
            raise ZenLangError(Diagnostic("ZEN302", "import paths must not be empty", statement.path.span))
        if "\0" in relative:
            raise ZenLangError(Diagnostic("ZEN302", "import paths cannot contain NUL bytes", statement.path.span))
        candidate = Path(relative)
        if candidate.is_absolute() or "://" in relative:
            raise ZenLangError(
                Diagnostic("ZEN302", "imports must use relative filesystem paths", statement.path.span)
            )
        self.import_count += 1
        if self.import_count > _MAX_IMPORTS:
            raise ZenLangError(
                Diagnostic("ZEN309", f"import count exceeds the maximum of {_MAX_IMPORTS}", statement.path.span)
            )
        target = _resolve_path(
            current_path.parent / candidate,
            relative,
            code="ZEN304",
            message="cannot resolve imported file",
            span=statement.path.span,
        )
        _require_within_root(target, self.root, statement.path.span)
        try:
            target_kind = FileKind.from_source(str(target))
        except ZenLangError as error:
            raise ZenLangError(
                Diagnostic("ZEN303", f"import must use the same .{kind.value} file extension", statement.path.span)
            ) from error
        if target_kind is not kind:
            raise ZenLangError(
                Diagnostic("ZEN303", f"import must use the same .{kind.value} file extension", statement.path.span)
            )
        return self.load(target, str(target), statement.path.span, imported=True)


def _resolve_path(
    path: Path,
    label: str,
    *,
    code: str,
    message: str,
    span: Span,
) -> Path:
    try:
        return path.resolve()
    except (OSError, RuntimeError, ValueError) as error:
        raise ZenLangError(
            Diagnostic(code, f"{message}: {label}", span, notes=(str(error),))
        ) from error


def _require_within_root(
    path: Path,
    import_root: Path,
    span: Span,
    *,
    subject: str = "import",
) -> None:
    try:
        path.relative_to(import_root)
    except ValueError as error:
        raise ZenLangError(
            Diagnostic(
                "ZEN306",
                f"{subject} resolves outside the allowed root: {path}",
                span,
                notes=(f"import root: {import_root}",),
            )
        ) from error


def _read_source(
    path: Path,
    label: str,
    span: Span,
    *,
    imported: bool,
    remaining_total_bytes: int,
    root: Path,
) -> tuple[str, int]:
    description = "imported file" if imported else "source file"
    code = "ZEN304" if imported else "ZEN301"
    try:
        descriptor = _open_beneath(root, path)
    except (OSError, UnicodeError, ValueError) as error:
        raise ZenLangError(
            Diagnostic(
                code,
                f"cannot read {description}: {label}",
                span,
                notes=(str(error),),
            )
        ) from error

    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode):
            raise ZenLangError(
                Diagnostic(
                    code,
                    f"cannot read {description}: {label}",
                    span,
                    notes=("path is not a regular file",),
                )
            )
        if metadata.st_size > _MAX_SOURCE_BYTES:
            _raise_source_too_large(label, span, imported=imported)
        if metadata.st_size > remaining_total_bytes:
            _raise_total_source_too_large(span)

        chunks: list[bytes] = []
        remaining = min(_MAX_SOURCE_BYTES, remaining_total_bytes) + 1
        while remaining:
            chunk = os.read(descriptor, min(64 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
        if len(data) > _MAX_SOURCE_BYTES:
            _raise_source_too_large(label, span, imported=imported)
        if len(data) > remaining_total_bytes:
            _raise_total_source_too_large(span)
        return data.decode("utf-8"), len(data)
    except ZenLangError:
        raise
    except (OSError, UnicodeError, ValueError) as error:
        raise ZenLangError(
            Diagnostic(
                code,
                f"cannot read {description}: {label}",
                span,
                notes=(str(error),),
            )
        ) from error
    finally:
        os.close(descriptor)


def _open_beneath(root: Path, path: Path) -> int:
    relative = path.relative_to(root)
    directory_flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_DIRECTORY
    file_flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
    descriptor = os.open(root, directory_flags)
    try:
        parts = relative.parts
        if not parts:
            raise OSError("source path resolves to the import root directory")
        for part in parts[:-1]:
            next_descriptor = os.open(part, directory_flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = next_descriptor
        return os.open(parts[-1], file_flags, dir_fd=descriptor)
    finally:
        os.close(descriptor)


def _raise_source_too_large(
    label: str, span: Span, *, imported: bool
) -> None:
    description = "imported file" if imported else "source file"
    raise ZenLangError(
        Diagnostic(
            "ZEN308",
            f"{description} exceeds the maximum size of {_MAX_SOURCE_BYTES} bytes: {label}",
            span,
        )
    )


def _raise_total_source_too_large(span: Span) -> None:
    raise ZenLangError(
        Diagnostic(
            "ZEN310",
            "aggregate source size exceeds the maximum of "
            f"{_MAX_TOTAL_SOURCE_BYTES} bytes",
            span,
        )
    )


def _import_path(statement: ImportStatement) -> str:
    if not isinstance(statement.path, StringExpr):
        return statement.path.value
    if any(isinstance(part, Interpolation) for part in statement.path.parts):
        raise ZenLangError(
            Diagnostic("ZEN302", "import paths cannot contain interpolation", statement.path.span)
        )
    return "".join(part.value for part in statement.path.parts if isinstance(part, StringText))


def tokenize(text: str, source: str) -> tuple[Token, ...]:
    FileKind.from_source(source)
    return lex(text, source)
