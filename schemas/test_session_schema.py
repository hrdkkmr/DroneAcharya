"""Independent JSON-Schema validation of the session format (run from the workspace root):
    python -m unittest discover -s schemas -v
"""
import copy
import json
import unittest
from pathlib import Path

import jsonschema

HERE = Path(__file__).resolve().parent
SCHEMA = json.loads((HERE / "droneacharya-session-1.schema.json").read_text(encoding="utf-8"))
EXAMPLE = json.loads((HERE / "examples" / "session_example.json").read_text(encoding="utf-8"))
VALIDATOR = jsonschema.Draft202012Validator(SCHEMA)


class SessionSchemaTests(unittest.TestCase):
    def test_schema_is_valid_draft_2020_12(self):
        jsonschema.Draft202012Validator.check_schema(SCHEMA)

    def test_example_session_is_valid(self):
        errors = [f"{list(e.absolute_path)}: {e.message}" for e in VALIDATOR.iter_errors(EXAMPLE)]
        self.assertEqual(errors, [])

    def test_example_keeps_truth_separate(self):
        for row in EXAMPLE["observations"]["rows"]:
            self.assertEqual(len(row), len(EXAMPLE["observations"]["columns"]))
        for column in EXAMPLE["observations"]["columns"]:
            self.assertNotIn(column, {"actor_id", "profile", "truth_category"})
        self.assertIn("links", EXAMPLE["truth"])

    def test_invalid_variants_are_rejected(self):
        mutations = {
            "missing evaluation": lambda r: r.pop("evaluation"),
            "unknown status": lambda r: r.__setitem__("status", "won"),
            "score above 100": lambda r: r["evaluation"].__setitem__("score", 140),
            "wrong format version": lambda r: r.__setitem__("format_version", 2),
            "unknown event type": lambda r: r["events"][0].__setitem__("type", "teleported"),
            "short observation row": lambda r: r["observations"]["rows"][0].pop(),
            "unknown action kind": lambda r: next(e for e in r["events"] if e["type"] == "action")["data"].__setitem__("kind", "engage"),
        }
        for name, mutate in mutations.items():
            record = copy.deepcopy(EXAMPLE)
            mutate(record)
            self.assertFalse(VALIDATOR.is_valid(record), name)


if __name__ == "__main__":
    unittest.main()
