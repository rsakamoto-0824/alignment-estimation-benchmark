import json
from pathlib import Path

import pytest

from src.geometry import build_layout

CONFIG_PATH = Path(__file__).resolve().parents[1] / "config" / "default.json"


@pytest.fixture(scope="session")
def config():
    with open(CONFIG_PATH, encoding="utf-8") as handle:
        return json.load(handle)


@pytest.fixture(scope="session")
def layout(config):
    return build_layout(config)
