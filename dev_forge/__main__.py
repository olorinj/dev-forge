"""Executable module entrypoint for python -m dev_forge."""

import sys
from dev_forge.cli import main

if __name__ == "__main__":
    main(sys.argv[1:])
