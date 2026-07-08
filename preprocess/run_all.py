"""run_all: 01〜05 を順次実行し、最後に §7 受け入れ条件の検証結果を
README.md の自動記録セクションへ書き込む。

使い方:
    .venv/bin/python run_all.py [--force] [--geom-decimals N]

--force          01 のOSM再取得を強制
--geom-decimals  geometry の座標丸め桁数 (既定6。§7.8 サイズ超過時は 5)
"""

from __future__ import annotations

import argparse
import datetime
import subprocess
import sys
from pathlib import Path

from pipeline_common import VERIFICATION_JSON, read_json, setup_logging

logger = setup_logging("run_all")

BASE_DIR = Path(__file__).resolve().parent
README_PATH = BASE_DIR / "README.md"
MARKER_BEGIN = "<!-- ACCEPTANCE_RESULTS:BEGIN -->"
MARKER_END = "<!-- ACCEPTANCE_RESULTS:END -->"


def run_step(script: str, extra_args: list[str]) -> int:
    logger.info("========== %s ==========", script)
    proc = subprocess.run([sys.executable, str(BASE_DIR / script), *extra_args])
    return proc.returncode


def render_results_markdown(report: dict) -> str:
    lines = [
        MARKER_BEGIN,
        "",
        f"- 検証日時: {report['verified_at']}",
        f"- DB: `{report['db_path']}` ({report['db_size_bytes'] / (1024 * 1024):.1f} MB)",
        f"- 総合判定: **{'全て合格' if report['all_passed'] else '不合格あり'}**",
        "",
        "| # | 受け入れ条件 | 基準 | 実測値 | 判定 |",
        "|---|---|---|---|---|",
    ]
    for c in report["checks"]:
        mark = "✅ PASS" if c["passed"] else "❌ FAIL"
        lines.append(
            f"| {c['no']} | {c['name']} | {c['criterion']} | {c['measured']} | {mark} |"
        )
    lines += ["", MARKER_END]
    return "\n".join(lines)


def update_readme(report: dict) -> None:
    text = README_PATH.read_text(encoding="utf-8")
    begin = text.find(MARKER_BEGIN)
    end = text.find(MARKER_END)
    if begin == -1 or end == -1:
        logger.warning("README.md にマーカーが無いため末尾に追記")
        text = text.rstrip() + "\n\n## 受け入れ条件 検証結果 (§7)\n\n" + render_results_markdown(report) + "\n"
    else:
        text = text[:begin] + render_results_markdown(report) + text[end + len(MARKER_END):]
    README_PATH.write_text(text, encoding="utf-8")
    logger.info("README.md に検証結果を記録")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--geom-decimals", type=int, default=6)
    args = parser.parse_args()

    steps = [
        ("01_fetch_osm.py", ["--force"] if args.force else []),
        ("02_build_graph.py", ["--geom-decimals", str(args.geom_decimals)]),
        ("03_fetch_elevation.py", []),
        ("04_build_shelters.py", []),
    ]
    for script, extra in steps:
        rc = run_step(script, extra)
        if rc != 0:
            logger.error("%s が失敗 (exit=%d)。中断", script, rc)
            return rc

    # 05 は検証失敗でも README へ実測値を記録してから同じ終了コードを返す
    rc = run_step("05_write_db.py", [])

    if VERIFICATION_JSON.exists():
        report = read_json(VERIFICATION_JSON)
        update_readme(report)
        logger.info("---- 受け入れ条件サマリ (%s) ----",
                    "全て合格" if report["all_passed"] else "不合格あり")
        for c in report["checks"]:
            logger.info("  [%s] §7-%d %s — %s",
                        "PASS" if c["passed"] else "FAIL", c["no"], c["name"], c["measured"])
    else:
        logger.error("verification.json が生成されていない")
        return rc or 1

    logger.info("run_all 完了 (%s)", datetime.datetime.now().isoformat(timespec="seconds"))
    return rc


if __name__ == "__main__":
    sys.exit(main())
