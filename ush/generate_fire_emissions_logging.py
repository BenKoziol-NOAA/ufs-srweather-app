import logging
from pathlib import Path


def init_logging() -> None:
    logging.basicConfig(
        filename=Path(
            "/work/noaa/epic/bwkoziol/sandbox/nco_dirs/test_smoke_dust/com/output/logs/20190722/gew.log"
        ),
        filemode="w",
        level=logging.DEBUG,
    )


init_logging()
GEWLOG = logging.getLogger("gew")
