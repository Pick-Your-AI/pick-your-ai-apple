"""Checks that remain active when Python runs with -O or PYTHONOPTIMIZE."""


def require(condition, message):
    if not condition:
        raise ValueError(message)
