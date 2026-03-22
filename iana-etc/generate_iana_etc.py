#!/usr/bin/env python3

import csv
import pathlib
import re
import sys

IGNORE_PATTERN = re.compile(r".*(unassigned|deprecated|reserved|historic).*", re.IGNORECASE)


def has_spaces(value: str) -> bool:
    return any(ch.isspace() for ch in value)


def write_services(source: pathlib.Path, dest: pathlib.Path) -> None:
    seen = set()
    with source.open(newline="") as src, dest.open("w", encoding="utf-8") as out:
        out.write("# See also services(5) and IANA official page :\n")
        out.write("# https://www.iana.org/assignments/service-names-port-numbers\n")
        out.write("#\n")
        out.write("# Generated from the IANA service-names-port-numbers.csv registry.\n")
        for row in csv.DictReader(src):
            desc = row["Description"].replace("\n", " ").strip()
            name = row["Service Name"].strip()
            protocol = row["Transport Protocol"].strip().lower()
            number = row["Port Number"].strip()

            if (
                IGNORE_PATTERN.match(desc)
                or not name
                or has_spaces(name)
                or not protocol
                or not number
            ):
                continue

            assignment = f"{number.split('-', 1)[0]}/{protocol}"
            entry = f"{name.lower().replace('_', '-'):16} {assignment:10}"
            if entry in seen:
                continue
            seen.add(entry)

            out.write(entry)
            if desc and len(desc) < 70:
                out.write(f" # {desc}")
            out.write("\n")


def write_protocols(source: pathlib.Path, dest: pathlib.Path) -> None:
    with source.open(newline="") as src, dest.open("w", encoding="utf-8") as out:
        out.write("# See also protocols(5) and IANA official page :\n")
        out.write("# https://www.iana.org/assignments/protocol-numbers\n")
        out.write("#\n")
        out.write("# Generated from the IANA protocol-numbers-1.csv registry.\n")
        for row in csv.DictReader(src):
            desc = row["Protocol"].replace("\n", " ").strip()
            keyword = row["Keyword"].strip()
            value = row["Decimal"].strip()

            if (
                IGNORE_PATTERN.match(desc)
                or IGNORE_PATTERN.match(keyword)
                or not keyword
                or has_spaces(keyword)
                or not value
            ):
                continue

            alias = keyword.split()[0]
            out.write(f"{alias.lower():16} {value + ' ' + alias:16}")
            if desc and len(desc) < 70:
                out.write(f" # {desc}")
            out.write("\n")


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: generate_iana_etc.py <services.csv> <protocols.csv> <part_dir>",
            file=sys.stderr,
        )
        return 1

    part_dir = pathlib.Path(sys.argv[3])
    etc_dir = part_dir / "etc"
    etc_dir.mkdir(parents=True, exist_ok=True)

    write_services(pathlib.Path(sys.argv[1]), etc_dir / "services")
    write_protocols(pathlib.Path(sys.argv[2]), etc_dir / "protocols")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
