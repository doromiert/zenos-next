from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Sequence, TextIO

from .diagnostics import render_human, render_json
from .engine import Loader, compile_nix
from .model import Diagnostic, Span, ZcfgError, document_to_dict


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="zcfg",
        description="Validate and compile the restricted Zen configuration DSL.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    check = subparsers.add_parser("check", help="validate a zcfg source tree")
    _add_common_arguments(check)

    compile_command = subparsers.add_parser(
        "compile", help="compile a zcfg source tree to a Nix function"
    )
    _add_common_arguments(compile_command)
    compile_command.add_argument(
        "-o",
        "--output",
        default="-",
        help="output file, or - for stdout (default: -)",
    )

    ast = subparsers.add_parser("ast", help="print the unmerged source AST as JSON")
    _add_common_arguments(ast)
    return parser


def _add_common_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("file", help="entry .zcfg file")
    parser.add_argument(
        "--diagnostic-format",
        choices=("human", "json"),
        default="human",
        help="error output format (default: human)",
    )


def main(
    argv: Sequence[str] | None = None,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
) -> int:
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    arguments = build_parser().parse_args(argv)
    loader = Loader()
    try:
        if arguments.command == "ast":
            document = loader.read_document(arguments.file)
            json.dump(
                document_to_dict(document),
                stdout,
                indent=2,
                sort_keys=True,
                ensure_ascii=False,
            )
            stdout.write("\n")
            return 0

        value = loader.load(arguments.file)
        if arguments.command == "check":
            if arguments.diagnostic_format == "json":
                stdout.write(render_json([]) + "\n")
            return 0

        output = compile_nix(value)
        if arguments.output == "-":
            stdout.write(output)
        else:
            _write_output(Path(arguments.output), output)
        return 0
    except ZcfgError as error:
        _write_diagnostic(error.diagnostic, arguments.diagnostic_format, loader, stderr)
        return 1


def _write_output(path: Path, output: str) -> None:
    try:
        path.write_text(output, encoding="utf-8")
    except OSError as error:
        raise ZcfgError(
            Diagnostic(
                "ZCFG304",
                f"cannot write output file: {path}",
                Span.point(str(path)),
                notes=(str(error),),
            )
        ) from error


def _write_diagnostic(
    diagnostic: Diagnostic,
    output_format: str,
    loader: Loader,
    stderr: TextIO,
) -> None:
    if output_format == "json":
        stderr.write(render_json([diagnostic]) + "\n")
    else:
        stderr.write(render_human(diagnostic, loader.sources) + "\n")
