#!/usr/bin/env python3
"""Execute each pinned SDK value in Elm and write the reference corpus.

Usage: python3 pkgs/morphir-sdk/conformance/run_elm_oracle.py \
  --elm-checkout /path/to/finos/morphir-elm

Requires Elm 0.19.1 (through mise), Node, and cached elm/core 1.0.5,
elm/json 1.1.3, elm/regex 1.0.0, chain-partners/elm-bignum 1.0.1.
"""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from oracle_cases import CASES
from oracle_boundary_cases import BOUNDARIES
from oracle_scheme_cases import expression as scheme_expression

HERE = Path(__file__).resolve().parent
PIN = "bc99af69a8b24d391311fae3822a87eafef3c334"
ELM_PACKAGES = {"elm/core": "1.0.5", "elm/json": "1.1.3", "chain-partners/elm-bignum": "1.0.1"}
SOURCE_MODULES = ("Decimal", "Int", "List", "Maybe")
DECIMAL_VALUES = {"from-int", "from-float", "hundred", "thousand", "million", "tenth", "hundredth", "thousandth", "millionth", "bps", "add", "sub", "negate", "mul", "div-with-default", "truncate", "round", "abs", "shift-decimal-left", "shift-decimal-right", "zero", "one", "minus-one"}
DICT_VALUES = {"empty", "singleton", "insert", "update", "remove", "from-list", "map", "filter", "union", "intersect", "diff"}
SET_VALUES = {"empty", "singleton", "insert", "remove", "from-list", "map", "filter", "union", "intersect", "diff"}


def projection(module, name, expression):
    if expression is None:
        return '"<not executed>"'
    if module == "decimal":
        if name in DECIMAL_VALUES:
            return f"D.toString ({expression})"
        if name in ("from-string", "div"):
            return f"M.map D.toString ({expression})"
    if module == "dict":
        if name in DICT_VALUES:
            return f"Dict.toList ({expression})"
        if name == "partition":
            return f"Tuple.mapBoth Dict.toList Dict.toList ({expression})"
    if module == "set":
        if name in SET_VALUES:
            return f"Set.toList ({expression})"
        if name == "partition":
            return f"Tuple.mapBoth Set.toList Set.toList ({expression})"
    if module == "int":
        if name == "to-int8":
            return f"M.map I.fromInt8 ({expression})"
        if name == "to-int16":
            return f"M.map I.fromInt16 ({expression})"
        if name == "to-int32":
            return f"M.map I.fromInt32 ({expression})"
    return expression


def command(argv, cwd):
    return subprocess.run(argv, cwd=cwd, check=True, text=True, capture_output=True).stdout


def build_source(entries):
    header = '''port module Main exposing (main)
import Basics
import Char as C
import Debug
import Dict
import Json.Encode as E
import List as L
import Maybe as M
import Morphir.SDK.Decimal as D
import Morphir.SDK.Int as I
import Morphir.SDK.List as ML
import Morphir.SDK.Maybe as MM
import Platform
import Result as R
import Set
import String as S
import Tuple

port output : E.Value -> Cmd msg

decimal : String -> D.Decimal
decimal source = M.withDefault D.zero (D.fromString source)

cases : List E.Value
cases =
    [
'''
    rows = []
    for entry in entries:
        module, name = entry["fqName"].split(":", 1)[1].split("#")
        projected = projection(module, name, entry["expression"])
        case_id = json.dumps(entry["id"], ensure_ascii=False)
        rows.append(f'      E.object [ ( "id", E.string {case_id} ), ( "result", E.string (Debug.toString ({projected})) ) ]')
    footer = '''    ]

main : Program () () msg
main =
    Platform.worker
        { init = \\_ -> ( (), output (E.list identity cases) )
        , update = \\_ model -> ( model, Cmd.none )
        , subscriptions = \\_ -> Sub.none
        }
'''
    return header + "\n    ,\n".join(rows) + "\n" + footer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--elm-checkout", required=True, type=Path)
    args = parser.parse_args()
    checkout = args.elm_checkout.resolve()
    command(["git", "cat-file", "-e", PIN + "^{commit}"], checkout)
    inventory = json.loads((HERE / "bindings.json").read_text())["values"]
    names = {value["fqName"] for value in inventory}
    mapped = {f"morphir/SDK:{module}#{name}" for module, cases in CASES.items() for name in cases}
    if names != mapped or len(inventory) != 248:
        raise SystemExit(f"case map differs from inventory: missing={sorted(names - mapped)}, extra={sorted(mapped - names)}")
    entries = []
    inventory_by_name = {value["fqName"]: value for value in inventory}
    for value in inventory:
        fq = value["fqName"]
        module, name = fq.split(":", 1)[1].split("#")
        elm_expression = CASES[module][name]
        reason = None
        if fq == "morphir/SDK:basics#never":
            reason = "Never has no inhabitant to pass to the function"
        elif module == "int" and name in ("from-int64", "to-int64"):
            reason = "Pinned Elm toInt64 compiles its lower bound to invalid JavaScript: --9223372036854775808"
        entries.append({"id": fq + "/normal", "fqName": fq,
                        "kind": "normal", "expression": elm_expression,
                        "schemeExpression": scheme_expression(module, name),
                        "executed": elm_expression is not None,
                        "unexecutedReason": reason,
                        "specSource": value["specSource"],
                        "semanticSource": value["semanticSource"]})
    for module, name, label, elm_expression, scheme in BOUNDARIES:
        fq = f"morphir/SDK:{module}#{name}"
        if fq not in names:
            raise SystemExit(f"boundary case names unknown value: {fq}")
        entries.append({"id": fq + "/boundary/" + label, "fqName": fq,
                        "kind": "boundary", "expression": elm_expression,
                        "schemeExpression": scheme, "executed": True,
                        "unexecutedReason": None,
                        "specSource": inventory_by_name[fq]["specSource"],
                        "semanticSource": inventory_by_name[fq]["semanticSource"]})
    with tempfile.TemporaryDirectory(prefix="morphir-elm-oracle-") as work:
        root = Path(work)
        modules = root / "src" / "Morphir" / "SDK"
        modules.mkdir(parents=True)
        for module in SOURCE_MODULES:
            source_path = f"src/Morphir/SDK/{module}.elm"
            (modules / f"{module}.elm").write_text(
                command(["git", "show", f"{PIN}:{source_path}"], checkout)
            )
        (root / "elm.json").write_text(json.dumps({
            "type": "application", "source-directories": ["src"], "elm-version": "0.19.1",
            "dependencies": {"direct": ELM_PACKAGES, "indirect": {"elm/regex": "1.0.0"}},
            "test-dependencies": {"direct": {}, "indirect": {}},
        }))
        (root / "src" / "Main.elm").write_text(build_source(entries))
        try:
            command(["mise", "exec", "elm@0.19.1", "--", "elm", "make", "src/Main.elm", "--output=oracle.js"], root)
        except subprocess.CalledProcessError as error:
            print(error.stdout)
            print(error.stderr)
            raise
        node = 'const {Elm}=require("./oracle.js");Elm.Main.init({flags:null}).ports.output.subscribe(v=>console.log(JSON.stringify(v)))'
        try:
            output = command(["node", "-e", node], root)
        except subprocess.CalledProcessError as error:
            print(error.stdout)
            print(error.stderr)
            raise
        result = json.loads(output.strip().splitlines()[-1])
    if len(result) != len(entries) or {item["id"] for item in result} != {entry["id"] for entry in entries}:
        raise SystemExit("Elm output does not cover the generated cases")
    by_id = {item["id"]: item["result"] for item in result}
    fixtures = {
        "source": {"repository": "finos/morphir-elm", "commit": PIN,
                   "elm": "0.19.1", "packages": ELM_PACKAGES,
                   "indirectPackages": {"elm/regex": "1.0.0"},
                   "modules": {"core": "elm/core", "custom": [f"src/Morphir/SDK/{module}.elm" for module in SOURCE_MODULES]}},
        "cases": [{**entry,
                   "projection": projection(*entry["fqName"].split(":", 1)[1].split("#"), entry["expression"]),
                   "elmDebug": by_id[entry["id"]]} for entry in entries],
    }
    destination = HERE / "elm_oracle.json"
    destination.write_text(json.dumps(fixtures, ensure_ascii=False, indent=2) + "\n")
    print(f"Wrote {len(result)} pinned cases to {destination}")


if __name__ == "__main__":
    main()
