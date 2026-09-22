#!/usr/bin/env python3
"""Export deterministic Russian and English frequency TSV from wordfreq."""

from __future__ import annotations

import argparse
import importlib.metadata
import sys
import unicodedata
from pathlib import Path

import wordfreq


EXPECTED_VERSION = "3.1.1"
MINIMUM_SCORE = 2500
ALLOWED_PUNCTUATION = frozenset(".+#-_/\\@'\"")


def normalize(term: str) -> str:
    quoted = term.translate(
        str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"'})
    )
    return " ".join(unicodedata.normalize("NFC", quoted).lower().split())


def is_language_letter(character: str, language: str) -> bool:
    if not character.isalpha():
        return False
    name = unicodedata.name(character, "")
    return (language == "en" and "LATIN" in name) or (
        language == "ru" and "CYRILLIC" in name
    )


def valid_term(term: str, language: str) -> bool:
    if not term or len(term) > 128 or len(term.split(" ")) > 8:
        return False
    letters = [character for character in term if character.isalpha()]
    if not letters or not all(is_language_letter(character, language) for character in letters):
        return False
    return all(
        character.isalpha()
        or character.isdecimal()
        or character == " "
        or character in ALLOWED_PUNCTUATION
        for character in term
    )


def export(output: Path) -> None:
    version = importlib.metadata.version("wordfreq")
    if version != EXPECTED_VERSION:
        raise RuntimeError(
            f"wordfreq {EXPECTED_VERSION} is required, found {version}"
        )

    rows: list[tuple[str, int, str]] = []
    for language in ("en", "ru"):
        terms: dict[str, int] = {}
        for raw_term in wordfreq.iter_wordlist(language, wordlist="large"):
            term = normalize(raw_term)
            if not valid_term(term, language):
                continue
            score = round(wordfreq.zipf_frequency(term, language, wordlist="large") * 1000)
            if MINIMUM_SCORE <= score <= 8000:
                terms[term] = max(score, terms.get(term, 0))
        rows.extend((language, score, term) for term, score in terms.items())

    rows.sort(key=lambda row: (row[0], row[2].encode("utf-8")))
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        for language, score, term in rows:
            stream.write(f"{language}\t{score}\t{term}\n")
        stream.flush()
    temporary.replace(output)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    export(arguments.output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # actionable single-line build-tool failure
        print(f"export-wordfreq: {error}", file=sys.stderr)
        raise SystemExit(1)
