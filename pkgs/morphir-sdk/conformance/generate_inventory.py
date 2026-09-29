#!/usr/bin/env python3
"""Extract pinned Morphir SDK value specs and map MoonBit package bindings."""
import argparse
import json
import re
import subprocess
from pathlib import Path

PIN = "bc99af69a8b24d391311fae3822a87eafef3c334"
MODULES = ("Basics", "String", "List", "Maybe", "Result", "Dict", "Set", "Char", "Int", "Decimal")
SPECIAL = {
    ("Basics", "add"): ("add_int", "add_float"),
    ("Basics", "subtract"): ("subtract_int", "subtract_float"),
    ("Basics", "multiply"): ("multiply_int", "multiply_float"),
    ("Basics", "power"): ("power_int", "power_float"),
    ("Basics", "negate"): ("negate_int", "negate_float"),
    ("Basics", "abs"): ("abs_int", "abs_float"),
    ("Basics", "clamp"): ("clamp_int", "clamp_float"),
    ("Basics", "append"): ("append_string", "append_list"),
    ("Basics", "not"): ("not_",),
    ("Basics", "and"): ("and_",),
    ("Basics", "or"): ("or_",),
    ("Basics", "isNaN"): ("is_nan",),
}


def function_name(name):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name).lower()


def show(checkout, path):
    return subprocess.check_output(
        ["git", "-C", str(checkout), "show", f"{PIN}:{path}"], text=True
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--elm-checkout", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("bindings.json"))
    args = parser.parse_args()
    sdk = Path(__file__).resolve().parents[1]
    inventory = []
    for module in MODULES:
        package = module.lower()
        source_path = f"src/Morphir/IR/SDK/{module}.elm"
        source = show(args.elm_checkout, source_path)
        declarations = set()
        for mbt in (sdk / package).glob("*.mbt"):
            if "_test" in mbt.name:
                continue
            declarations.update(re.findall(r"\bpub fn(?:\[[^]]+\])?\s+([A-Za-z0-9_]+)\s*\(", mbt.read_text()))
        for match in re.finditer(r'\bvSpec\s+"([^"]+)"', source):
            name = match.group(1)
            delimiter = re.search(r"\n            (?:, vSpec|\])", source[match.start():])
            if not delimiter:
                raise RuntimeError(f"No signature terminator for {module}.{name}")
            signature = source[match.start(): match.start() + delimiter.start()].strip()
            bindings = SPECIAL.get((module, name), (function_name(name),))
            semantic_source = "elm/core 1.0.5"
            if module == "Int":
                semantic_source = f"finos/morphir-elm {PIN}: src/Morphir/SDK/Int.elm"
            elif module == "Decimal":
                semantic_source = f"finos/morphir-elm {PIN}: src/Morphir/SDK/Decimal.elm; chain-partners/elm-bignum 1.0.1"
            elif module == "List" and name in ("innerJoin", "leftJoin"):
                semantic_source = f"finos/morphir-elm {PIN}: src/Morphir/SDK/List.elm"
            inventory.append({
                "fqName": f"morphir/SDK:{package}#{function_name(name).replace('_', '-')}",
                "elmName": name,
                "specification": signature,
                "specSource": f"{source_path}:{source.count(chr(10), 0, match.start()) + 1}@{PIN}",
                "semanticSource": semantic_source,
                "moonbitBindings": [f"finos/morphir-sdk/{package}:{binding}" for binding in bindings if binding in declarations],
                "moduleTests": sorted(
                    f"{package}/{p.name}"
                    for p in (sdk / package).glob("*.mbt")
                    if p.name.endswith(("_test.mbt", "_wbtest.mbt"))
                ),
                "conformance": "pending-oracle-fixtures",
            })
    if len(inventory) != 248:
        raise RuntimeError(f"Expected 248 values; got {len(inventory)}")
    args.output.write_text(json.dumps({"pin": PIN, "values": inventory}, indent=2, ensure_ascii=False) + "\n")
    missing = [entry["fqName"] for entry in inventory if not entry["moonbitBindings"]]
    print(f"{len(inventory)} values, {len(missing)} without a MoonBit binding")
    for name in missing:
        print(f"  {name}")


if __name__ == "__main__":
    main()
