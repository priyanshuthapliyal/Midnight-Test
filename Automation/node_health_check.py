#!/usr/bin/env python3
"""
Midnight Preprod Substrate Node Health Checker.

Evaluates node reachability, peer count, sync progress, finality lag,
block progression, and local disk space using Python 3 standard library only.
Produces timestamped JSON reports, maintains latest.json/previous.json
symlinks atomically, and detects regressions across polling intervals.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import signal
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


# Exit codes
EXIT_HEALTHY = 0
EXIT_DEGRADED = 1
EXIT_UNHEALTHY = 2

# Status ordering for regression comparison
STATUS_RANK = {
    "HEALTHY": 0,
    "DEGRADED": 1,
    "UNHEALTHY": 2,
}

# Prometheus metric line pattern:
# metric_name{label1="val1",...} 123.45 [optional_timestamp]
PROM_LINE_RE = re.compile(
    r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{([^}]*)\})?\s+([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?|NaN|[+-]?Inf)(?:\s+\S+)?$"
)
PROM_LABEL_RE = re.compile(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*"((?:[^"\\]|\\.)*)"')

_STOP_REQUESTED = False


def _handle_signal(signum: int, _frame: Any) -> None:
    """Gracefully stop the polling loop on SIGINT/SIGTERM."""
    global _STOP_REQUESTED
    _STOP_REQUESTED = True


def utc_now() -> dt.datetime:
    """Return current UTC datetime."""
    return dt.datetime.now(dt.timezone.utc)


def format_iso_utc(ts: dt.datetime) -> str:
    """Format a UTC datetime as ISO 8601 with Z suffix."""
    return ts.strftime("%Y-%m-%dT%H:%M:%SZ")


def format_filename_utc(ts: dt.datetime) -> str:
    """Format a UTC datetime for report filenames (YYYYMMDDTHHMMSSZ)."""
    return ts.strftime("%Y%m%dT%H%M%SZ")


def parse_iso_utc(value: str) -> Optional[dt.datetime]:
    """Parse an ISO 8601 UTC timestamp string safely."""
    if not value:
        return None
    try:
        if value.endswith("Z"):
            value = value[:-1] + "+00:00"
        return dt.datetime.fromisoformat(value)
    except ValueError:
        return None


def env_str(name: str, default: str) -> str:
    return os.environ.get(name, default)


def env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def env_float(name: str, default: float) -> float:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Health checker for a Midnight Preprod Substrate node.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--rpc-url",
        default=env_str("MIDNIGHT_RPC_URL", "http://127.0.0.1:9933"),
        help="Substrate JSON-RPC HTTP URL (env: MIDNIGHT_RPC_URL)",
    )
    parser.add_argument(
        "--metrics-url",
        default=env_str("MIDNIGHT_METRICS_URL", "http://127.0.0.1:9615/metrics"),
        help="Prometheus metrics endpoint URL (env: MIDNIGHT_METRICS_URL)",
    )
    parser.add_argument(
        "--output-dir",
        default=env_str("HEALTH_OUTPUT_DIR", "./health-reports"),
        help="Directory to store JSON health reports (env: HEALTH_OUTPUT_DIR)",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=env_int("POLL_INTERVAL", 60),
        help="Poll interval in seconds for continuous mode (env: POLL_INTERVAL)",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Run a single health check and exit",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=env_float("REQUEST_TIMEOUT", 5.0),
        help="HTTP request timeout in seconds (env: REQUEST_TIMEOUT)",
    )
    parser.add_argument(
        "--min-peers",
        type=int,
        default=env_int("MIN_PEERS", 3),
        help="Minimum healthy peer count (env: MIN_PEERS)",
    )
    parser.add_argument(
        "--max-sync-lag",
        type=int,
        default=env_int("MAX_SYNC_LAG", 50),
        help="Maximum acceptable blocks behind sync target (env: MAX_SYNC_LAG)",
    )
    parser.add_argument(
        "--max-finality-lag",
        type=int,
        default=env_int("MAX_FINALITY_LAG", 10),
        help="Maximum acceptable best - finalized block lag (env: MAX_FINALITY_LAG)",
    )
    parser.add_argument(
        "--min-block-time",
        type=int,
        default=env_int("MIN_BLOCK_TIME", 12),
        help="Minimum elapsed seconds before a flat best_block is flagged as stalled (env: MIN_BLOCK_TIME)",
    )
    parser.add_argument(
        "--max-stall-seconds",
        type=int,
        default=env_int("MAX_STALL_SECONDS", 120),
        help="Maximum elapsed seconds with no new block before failing (env: MAX_STALL_SECONDS)",
    )
    parser.add_argument(
        "--data-dir",
        default=env_str("DATA_DIR", "/data"),
        help="Local node data directory for disk space check (env: DATA_DIR)",
    )
    parser.add_argument(
        "--min-disk-free-pct",
        type=float,
        default=env_float("MIN_DISK_FREE_PCT", 15.0),
        help="Minimum free disk space percentage (env: MIN_DISK_FREE_PCT)",
    )
    parser.add_argument(
        "--skip-disk-check",
        action="store_true",
        help="Skip local disk space check",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Print machine-readable JSON report to stdout",
    )
    return parser


def rpc_call(
    url: str,
    method: str,
    params: Optional[List[Any]] = None,
    timeout: float = 5.0,
) -> Tuple[Optional[Any], Optional[str]]:
    """
    Execute a single JSON-RPC 2.0 POST call.

    Returns (result, error_message). Never raises on network or parse errors.
    """
    payload = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params or [],
        }
    ).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = getattr(resp, "status", 200)
            if status < 200 or status >= 300:
                return None, f"HTTP {status}"
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return None, f"HTTP {exc.code}: {exc.reason}"
    except urllib.error.URLError as exc:
        return None, f"Connection error: {exc.reason}"
    except (TimeoutError, socket.timeout):
        return None, f"Request timed out after {timeout}s"
    except Exception as exc:  # noqa: BLE001 - defensive boundary for stdlib HTTP errors
        return None, f"Unexpected RPC error: {exc}"

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        return None, f"Malformed JSON response: {exc}"

    if not isinstance(data, dict):
        return None, "Unexpected JSON-RPC response type"

    if "error" in data and data["error"] is not None:
        return None, f"JSON-RPC error: {data['error']}"

    if "result" not in data:
        return None, "Missing 'result' field in JSON-RPC response"

    return data["result"], None


def fetch_prometheus_metrics(
    url: str,
    timeout: float = 5.0,
) -> Tuple[Optional[List[Tuple[str, Dict[str, str], float]]], Optional[str]]:
    """
    Fetch and parse Prometheus text exposition metrics.

    Returns (parsed_samples, error_message) where parsed_samples is a list of
    (metric_name, labels_dict, float_value).
    """
    req = urllib.request.Request(url, headers={"Accept": "text/plain"}, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = getattr(resp, "status", 200)
            if status < 200 or status >= 300:
                return None, f"HTTP {status}"
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return None, f"HTTP {exc.code}: {exc.reason}"
    except urllib.error.URLError as exc:
        return None, f"Connection error: {exc.reason}"
    except (TimeoutError, socket.timeout):
        return None, f"Request timed out after {timeout}s"
    except Exception as exc:  # noqa: BLE001
        return None, f"Unexpected metrics error: {exc}"

    samples: List[Tuple[str, Dict[str, str], float]] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = PROM_LINE_RE.match(line)
        if not match:
            continue
        name, label_str, val_str = match.groups()
        try:
            value = float(val_str)
        except ValueError:
            continue
        labels: Dict[str, str] = {}
        if label_str:
            for lm in PROM_LABEL_RE.finditer(label_str):
                labels[lm.group(1)] = lm.group(2)
        samples.append((name, labels, value))

    return samples, None


def parse_hex_int(value: Any) -> Optional[int]:
    """Parse a Substrate hex block number (e.g. '0x1a2b') or int safely."""
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, str):
        try:
            return int(value, 16) if value.startswith(("0x", "0X")) else int(value)
        except ValueError:
            return None
    return None


def find_prom_metric(
    samples: Optional[List[Tuple[str, Dict[str, str], float]]],
    name: str,
    required_labels: Optional[Dict[str, str]] = None,
) -> Optional[int]:
    """Find the first matching Prometheus metric and return it as an int."""
    if not samples:
        return None
    for s_name, s_labels, s_val in samples:
        if s_name != name:
            continue
        if required_labels:
            if not all(s_labels.get(k) == v for k, v in required_labels.items()):
                continue
        if s_val != s_val:  # NaN check
            return None
        return int(s_val)
    return None


def collect_node_data(
    rpc_url: str,
    metrics_url: str,
    timeout: float,
) -> Dict[str, Any]:
    """Query RPC and Prometheus endpoints and normalize observed node metrics."""
    rpc_errors: Dict[str, str] = {}

    health_res, err = rpc_call(rpc_url, "system_health", timeout=timeout)
    if err:
        rpc_errors["system_health"] = err

    sync_res, err = rpc_call(rpc_url, "system_syncState", timeout=timeout)
    if err:
        rpc_errors["system_syncState"] = err

    best_header_res, err = rpc_call(rpc_url, "chain_getHeader", timeout=timeout)
    if err:
        rpc_errors["chain_getHeader"] = err

    fin_hash_res, err = rpc_call(rpc_url, "chain_getFinalizedHead", timeout=timeout)
    if err:
        rpc_errors["chain_getFinalizedHead"] = err

    fin_header_res = None
    if isinstance(fin_hash_res, str) and fin_hash_res.startswith("0x"):
        fin_header_res, err = rpc_call(
            rpc_url, "chain_getHeader", params=[fin_hash_res], timeout=timeout
        )
        if err:
            rpc_errors["chain_getHeader(finalized)"] = err

    prom_samples, prom_error = fetch_prometheus_metrics(metrics_url, timeout=timeout)

    rpc_reachable = any(
        res is not None
        for res in (health_res, sync_res, best_header_res, fin_hash_res)
    )
    metrics_reachable = prom_samples is not None

    # Extract normalized metrics with Prometheus fallback where applicable
    peers: Optional[int] = None
    is_syncing: Optional[bool] = None
    if isinstance(health_res, dict):
        raw_peers = health_res.get("peers")
        if isinstance(raw_peers, int) and not isinstance(raw_peers, bool):
            peers = raw_peers
        raw_syncing = health_res.get("isSyncing")
        if isinstance(raw_syncing, bool):
            is_syncing = raw_syncing

    if peers is None:
        peers = find_prom_metric(prom_samples, "substrate_sub_libp2p_peers_count")
        if peers is None:
            peers = find_prom_metric(prom_samples, "substrate_peers_count")

    best_block: Optional[int] = None
    if isinstance(best_header_res, dict):
        best_block = parse_hex_int(best_header_res.get("number"))
    if best_block is None:
        best_block = find_prom_metric(
            prom_samples, "substrate_block_height", {"status": "best"}
        )

    finalized_block: Optional[int] = None
    if isinstance(fin_header_res, dict):
        finalized_block = parse_hex_int(fin_header_res.get("number"))
    if finalized_block is None:
        finalized_block = find_prom_metric(
            prom_samples, "substrate_block_height", {"status": "finalized"}
        )

    current_block: Optional[int] = None
    highest_block: Optional[int] = None
    if isinstance(sync_res, dict):
        current_block = parse_hex_int(sync_res.get("currentBlock"))
        highest_block = parse_hex_int(sync_res.get("highestBlock"))

    if current_block is None:
        current_block = best_block
    if highest_block is None:
        highest_block = find_prom_metric(
            prom_samples, "substrate_block_height", {"status": "sync_target"}
        )

    blocks_behind: Optional[int] = None
    if current_block is not None and highest_block is not None:
        blocks_behind = max(0, highest_block - current_block)

    finality_lag: Optional[int] = None
    if best_block is not None and finalized_block is not None:
        # Guard against transient negative lag if RPC calls straddle a new block
        finality_lag = max(0, best_block - finalized_block)

    return {
        "rpc_reachable": rpc_reachable,
        "metrics_reachable": metrics_reachable,
        "rpc_errors": rpc_errors,
        "metrics_error": prom_error,
        "metrics": {
            "best_block": best_block,
            "finalized_block": finalized_block,
            "finality_lag": finality_lag,
            "peers": peers,
            "is_syncing": is_syncing,
            "blocks_behind": blocks_behind,
            "disk_free_pct": None,  # Populated by disk check
        },
    }


def check_disk_space(
    data_dir: str, min_disk_free_pct: float, skip: bool
) -> Tuple[Dict[str, Any], Optional[float]]:
    """Evaluate local disk free percentage on data_dir."""
    if skip:
        return {
            "status": "pass",
            "observed": None,
            "threshold": min_disk_free_pct,
            "message": "Disk check skipped (--skip-disk-check)",
        }, None

    path = Path(data_dir)
    if not path.exists():
        # Optional local check: do not fail if running remotely without local /data
        return {
            "status": "pass",
            "observed": None,
            "threshold": min_disk_free_pct,
            "message": f"Data directory '{data_dir}' not present locally; disk check skipped",
        }, None

    try:
        usage = shutil.disk_usage(path)
        if usage.total <= 0:
            return {
                "status": "warn",
                "observed": None,
                "threshold": min_disk_free_pct,
                "message": f"Unable to determine total disk size for '{data_dir}'",
            }, None
        free_pct = round((usage.free / usage.total) * 100.0, 2)
    except OSError as exc:
        return {
            "status": "warn",
            "observed": None,
            "threshold": min_disk_free_pct,
            "message": f"Failed to inspect disk usage for '{data_dir}': {exc}",
        }, None

    if free_pct < 5.0:
        status = "fail"
        msg = f"Critical disk space on '{data_dir}': {free_pct}% free (< 5.0%)"
    elif free_pct < min_disk_free_pct:
        status = "warn"
        msg = f"Low disk space on '{data_dir}': {free_pct}% free (< {min_disk_free_pct}%)"
    else:
        status = "pass"
        msg = f"Disk space healthy on '{data_dir}': {free_pct}% free"

    return {
        "status": status,
        "observed": free_pct,
        "threshold": min_disk_free_pct,
        "message": msg,
    }, free_pct


def evaluate_checks(
    collected: Dict[str, Any],
    prev_report: Optional[Dict[str, Any]],
    now: dt.datetime,
    args: argparse.Namespace,
) -> Dict[str, Dict[str, Any]]:
    """Evaluate all 6 health conditions and return structured check results."""
    metrics = collected["metrics"]
    rpc_reachable = collected["rpc_reachable"]
    metrics_reachable = collected["metrics_reachable"]
    checks: Dict[str, Dict[str, Any]] = {}

    # 1. Endpoint Reachability
    if not rpc_reachable and not metrics_reachable:
        checks["endpoint_reachability"] = {
            "status": "fail",
            "observed": {"rpc": False, "metrics": False},
            "threshold": "rpc_or_metrics_reachable",
            "message": "Both JSON-RPC and Prometheus metrics endpoints are unreachable",
        }
    elif not rpc_reachable:
        checks["endpoint_reachability"] = {
            "status": "fail",
            "observed": {"rpc": False, "metrics": True},
            "threshold": "rpc_reachable",
            "message": f"JSON-RPC unreachable ({collected['rpc_errors']}); Prometheus metrics reachable",
        }
    elif not metrics_reachable:
        checks["endpoint_reachability"] = {
            "status": "warn",
            "observed": {"rpc": True, "metrics": False},
            "threshold": "rpc_and_metrics_reachable",
            "message": f"JSON-RPC reachable; Prometheus metrics unreachable ({collected['metrics_error']})",
        }
    else:
        checks["endpoint_reachability"] = {
            "status": "pass",
            "observed": {"rpc": True, "metrics": True},
            "threshold": "rpc_and_metrics_reachable",
            "message": "JSON-RPC and Prometheus metrics endpoints are reachable",
        }

    # 2. Peer Count
    peers = metrics["peers"]
    if peers is None:
        checks["peer_count"] = {
            "status": "fail" if not rpc_reachable else "warn",
            "observed": None,
            "threshold": args.min_peers,
            "message": "Peer count unavailable",
        }
    elif peers == 0:
        checks["peer_count"] = {
            "status": "fail",
            "observed": 0,
            "threshold": args.min_peers,
            "message": "Node has 0 connected peers",
        }
    elif peers < args.min_peers:
        checks["peer_count"] = {
            "status": "warn",
            "observed": peers,
            "threshold": args.min_peers,
            "message": f"Low peer count: {peers} (< {args.min_peers})",
        }
    else:
        checks["peer_count"] = {
            "status": "pass",
            "observed": peers,
            "threshold": args.min_peers,
            "message": f"Peer count healthy: {peers} (>= {args.min_peers})",
        }

    # 3. Sync Progress & Lag
    is_syncing = metrics["is_syncing"]
    blocks_behind = metrics["blocks_behind"]
    if blocks_behind is None and is_syncing is None:
        checks["sync_progress"] = {
            "status": "fail" if not rpc_reachable else "warn",
            "observed": None,
            "threshold": args.max_sync_lag,
            "message": "Sync state unavailable",
        }
    elif blocks_behind is not None and blocks_behind > args.max_sync_lag:
        checks["sync_progress"] = {
            "status": "warn",
            "observed": blocks_behind,
            "threshold": args.max_sync_lag,
            "message": f"Node lagging behind sync target by {blocks_behind} blocks (> {args.max_sync_lag})",
        }
    elif is_syncing is True and blocks_behind is None:
        checks["sync_progress"] = {
            "status": "warn",
            "observed": "syncing",
            "threshold": args.max_sync_lag,
            "message": "Node reports isSyncing=true and sync target height is unavailable",
        }
    else:
        checks["sync_progress"] = {
            "status": "pass",
            "observed": blocks_behind if blocks_behind is not None else 0,
            "threshold": args.max_sync_lag,
            "message": f"Sync healthy (is_syncing={is_syncing}, blocks_behind={blocks_behind})",
        }

    # 4. Finality Lag
    finality_lag = metrics["finality_lag"]
    if finality_lag is None:
        checks["finality_lag"] = {
            "status": "fail" if not rpc_reachable else "warn",
            "observed": None,
            "threshold": args.max_finality_lag,
            "message": "Finality lag unavailable (missing best or finalized block)",
        }
    elif finality_lag > args.max_finality_lag:
        checks["finality_lag"] = {
            "status": "warn",
            "observed": finality_lag,
            "threshold": args.max_finality_lag,
            "message": f"High finality lag: {finality_lag} blocks (> {args.max_finality_lag})",
        }
    else:
        checks["finality_lag"] = {
            "status": "pass",
            "observed": finality_lag,
            "threshold": args.max_finality_lag,
            "message": f"Finality lag healthy: {finality_lag} blocks (<= {args.max_finality_lag})",
        }

    # 5. Block Progression (compare against previous report)
    best_block = metrics["best_block"]
    if prev_report is None:
        checks["block_progression"] = {
            "status": "pass",
            "observed": best_block,
            "threshold": "prev_best_block < best_block",
            "message": "First run (no previous report); baseline established",
        }
    else:
        prev_metrics = prev_report.get("metrics") or {}
        prev_best = prev_metrics.get("best_block")
        prev_ts = parse_iso_utc(prev_report.get("timestamp", ""))
        elapsed = (now - prev_ts).total_seconds() if prev_ts else None

        if best_block is None or prev_best is None:
            checks["block_progression"] = {
                "status": "warn" if rpc_reachable else "fail",
                "observed": best_block,
                "threshold": prev_best,
                "message": "Cannot verify block progression (missing current or previous best_block)",
            }
        elif best_block < prev_best:
            checks["block_progression"] = {
                "status": "fail",
                "observed": best_block,
                "threshold": f"> {prev_best}",
                "message": f"Best block decreased from {prev_best} to {best_block}",
            }
        elif best_block == prev_best:
            if elapsed is not None and elapsed >= args.max_stall_seconds:
                checks["block_progression"] = {
                    "status": "fail",
                    "observed": best_block,
                    "threshold": f"> {prev_best} within {args.max_stall_seconds}s",
                    "message": f"Chain stalled at block {best_block} for {int(elapsed)}s",
                }
            elif (
                elapsed is None or elapsed >= args.min_block_time
            ) and not is_syncing:
                checks["block_progression"] = {
                    "status": "warn",
                    "observed": best_block,
                    "threshold": f"> {prev_best}",
                    "message": f"Best block did not advance from {best_block} since previous check",
                }
            else:
                checks["block_progression"] = {
                    "status": "pass",
                    "observed": best_block,
                    "threshold": f"> {prev_best}",
                    "message": (
                        f"Best block unchanged at {best_block} within {int(elapsed)}s "
                        f"(< min_block_time {args.min_block_time}s)"
                        if elapsed is not None
                        else f"Best block at {best_block}"
                    ),
                }
        else:
            delta = best_block - prev_best
            checks["block_progression"] = {
                "status": "pass",
                "observed": best_block,
                "threshold": f"> {prev_best}",
                "message": f"Chain advanced by +{delta} blocks ({prev_best} -> {best_block})",
            }

    # 6. Disk Space
    disk_check, free_pct = check_disk_space(
        args.data_dir, args.min_disk_free_pct, args.skip_disk_check
    )
    checks["disk_space"] = disk_check
    metrics["disk_free_pct"] = free_pct

    return checks


def compute_overall_status(checks: Dict[str, Dict[str, Any]]) -> str:
    """Derive overall_status (HEALTHY, DEGRADED, UNHEALTHY) from individual checks."""
    statuses = [c["status"] for c in checks.values()]
    if "fail" in statuses:
        return "UNHEALTHY"
    if "warn" in statuses:
        return "DEGRADED"
    return "HEALTHY"


def detect_regressions(
    prev_report: Optional[Dict[str, Any]],
    curr_status: str,
    curr_metrics: Dict[str, Any],
    curr_rpc_reachable: bool,
    now: dt.datetime,
    args: argparse.Namespace,
) -> List[Dict[str, Any]]:
    """Compare current run against previous.json and surface explicit regressions."""
    if prev_report is None:
        return []

    regressions: List[Dict[str, Any]] = []
    prev_status = prev_report.get("overall_status", "HEALTHY")
    prev_metrics = prev_report.get("metrics") or {}
    prev_checks = prev_report.get("checks") or {}
    prev_ts = parse_iso_utc(prev_report.get("timestamp", ""))
    elapsed = (now - prev_ts).total_seconds() if prev_ts else None

    # 1. Overall status worsened
    if STATUS_RANK.get(curr_status, 0) > STATUS_RANK.get(prev_status, 0):
        regressions.append(
            {
                "type": "status_worsened",
                "severity": "critical" if curr_status == "UNHEALTHY" else "warning",
                "message": f"Overall status worsened: {prev_status} -> {curr_status}",
                "previous": prev_status,
                "current": curr_status,
            }
        )

    # 2. Node became unreachable
    prev_reach_obs = (prev_checks.get("endpoint_reachability") or {}).get("observed")
    prev_rpc_ok = (
        prev_reach_obs.get("rpc")
        if isinstance(prev_reach_obs, dict)
        else (prev_status != "UNHEALTHY")
    )
    if prev_rpc_ok and not curr_rpc_reachable:
        regressions.append(
            {
                "type": "node_unreachable",
                "severity": "critical",
                "message": "Node JSON-RPC endpoint became unreachable",
                "previous": True,
                "current": False,
            }
        )

    # 3. Peer count dropped below threshold or dropped by >= 50%
    prev_peers = prev_metrics.get("peers")
    curr_peers = curr_metrics.get("peers")
    if prev_peers is not None and curr_peers is not None:
        if prev_peers >= args.min_peers and curr_peers < args.min_peers:
            regressions.append(
                {
                    "type": "peers_below_threshold",
                    "severity": "warning",
                    "message": f"Peer count dropped below threshold ({args.min_peers}): {prev_peers} -> {curr_peers}",
                    "previous": prev_peers,
                    "current": curr_peers,
                }
            )
        elif prev_peers > 0 and curr_peers <= (prev_peers * 0.5):
            drop_pct = round(((prev_peers - curr_peers) / prev_peers) * 100.0, 1)
            regressions.append(
                {
                    "type": "peers_sharp_drop",
                    "severity": "warning",
                    "message": f"Peer count dropped by {drop_pct}%: {prev_peers} -> {curr_peers}",
                    "previous": prev_peers,
                    "current": curr_peers,
                }
            )

    # 4. Best block stalled or decreased
    prev_best = prev_metrics.get("best_block")
    curr_best = curr_metrics.get("best_block")
    if prev_best is not None and curr_best is not None:
        if curr_best < prev_best:
            regressions.append(
                {
                    "type": "best_block_decreased",
                    "severity": "critical",
                    "message": f"Best block decreased: {prev_best} -> {curr_best}",
                    "previous": prev_best,
                    "current": curr_best,
                }
            )
        elif curr_best == prev_best and (
            elapsed is None or elapsed >= args.min_block_time
        ):
            regressions.append(
                {
                    "type": "best_block_stalled",
                    "severity": "warning",
                    "message": f"Best block stalled at {curr_best} since previous check",
                    "previous": prev_best,
                    "current": curr_best,
                }
            )

    # 5. Finality lag grew beyond threshold
    prev_lag = prev_metrics.get("finality_lag")
    curr_lag = curr_metrics.get("finality_lag")
    if prev_lag is not None and curr_lag is not None:
        if prev_lag <= args.max_finality_lag and curr_lag > args.max_finality_lag:
            regressions.append(
                {
                    "type": "finality_lag_exceeded",
                    "severity": "warning",
                    "message": (
                        f"Finality lag grew beyond threshold ({args.max_finality_lag}): "
                        f"{prev_lag} -> {curr_lag}"
                    ),
                    "previous": prev_lag,
                    "current": curr_lag,
                }
            )

    return regressions


def load_previous_report(output_dir: Path) -> Optional[Dict[str, Any]]:
    """Load the most recent prior report (latest.json) if present and valid."""
    latest_path = output_dir / "latest.json"
    if not latest_path.exists():
        return None
    try:
        with latest_path.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else None
    except (OSError, json.JSONDecodeError):
        return None


def atomic_write_json(target: Path, payload: Dict[str, Any]) -> None:
    """Write JSON atomically using a temporary file in the same directory."""
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=f".{target.name}.", suffix=".tmp", dir=str(target.parent)
    )
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_path, target)
    except Exception:
        if tmp_path.exists():
            tmp_path.unlink(missing_ok=True)
        raise


def atomic_update_symlink(link_path: Path, target_name: str) -> None:
    """Atomically point link_path -> target_name (relative), falling back to copy."""
    tmp_link = link_path.parent / f".{link_path.name}.{os.getpid()}.tmp"
    try:
        if tmp_link.exists() or tmp_link.is_symlink():
            tmp_link.unlink()
        os.symlink(target_name, tmp_link)
        os.replace(tmp_link, link_path)
    except OSError:
        # Fallback if filesystem disallows symlinks
        if tmp_link.exists() or tmp_link.is_symlink():
            tmp_link.unlink(missing_ok=True)
        src = link_path.parent / target_name
        if src.exists():
            tmp_copy = link_path.parent / f".{link_path.name}.{os.getpid()}.copy"
            shutil.copy2(src, tmp_copy)
            os.replace(tmp_copy, link_path)


def save_report(output_dir: Path, report: Dict[str, Any], ts: dt.datetime) -> Path:
    """Persist timestamped report and rotate latest.json / previous.json atomically."""
    output_dir.mkdir(parents=True, exist_ok=True)
    report_name = f"report_{format_filename_utc(ts)}.json"
    report_path = output_dir / report_name

    # Avoid filename collision if run multiple times within the same second
    if report_path.exists():
        suffix = 1
        while (output_dir / f"report_{format_filename_utc(ts)}_{suffix}.json").exists():
            suffix += 1
        report_name = f"report_{format_filename_utc(ts)}_{suffix}.json"
        report_path = output_dir / report_name

    atomic_write_json(report_path, report)

    latest_link = output_dir / "latest.json"
    previous_link = output_dir / "previous.json"

    if latest_link.exists() or latest_link.is_symlink():
        if latest_link.is_symlink():
            prev_target = os.readlink(latest_link)
            atomic_update_symlink(previous_link, prev_target)
        else:
            # Non-symlink file fallback
            tmp_prev = output_dir / f".previous.json.{os.getpid()}.tmp"
            shutil.copy2(latest_link, tmp_prev)
            os.replace(tmp_prev, previous_link)

    atomic_update_symlink(latest_link, report_name)
    return report_path


def determine_exit_code(overall_status: str, regressions: List[Dict[str, Any]]) -> int:
    """Map overall_status and regressions to process exit code."""
    if overall_status == "UNHEALTHY":
        return EXIT_UNHEALTHY
    if overall_status == "DEGRADED" or len(regressions) > 0:
        return EXIT_DEGRADED
    return EXIT_HEALTHY


def format_human_summary(report: Dict[str, Any], report_path: Path) -> str:
    """Format a clean human-readable summary for stdout."""
    m = report["metrics"]
    lines = [
        f"=== Midnight Node Health Check [{report['timestamp']}] ===",
        f"Overall Status : {report['overall_status']}",
        f"Report File    : {report_path}",
        "",
        "Metrics:",
        f"  best_block      : {m['best_block']}",
        f"  finalized_block : {m['finalized_block']}",
        f"  finality_lag    : {m['finality_lag']}",
        f"  peers           : {m['peers']}",
        f"  is_syncing      : {m['is_syncing']}",
        f"  blocks_behind   : {m['blocks_behind']}",
        f"  disk_free_pct   : {m['disk_free_pct']}",
        "",
        "Checks:",
    ]
    for name, check in report["checks"].items():
        tag = check["status"].upper().ljust(4)
        lines.append(f"  [{tag}] {name}: {check['message']}")

    regressions = report.get("regressions") or []
    lines.append("")
    if regressions:
        lines.append(f"Regressions Detected ({len(regressions)}):")
        for reg in regressions:
            lines.append(f"  - [{reg['severity'].upper()}] {reg['message']}")
    else:
        lines.append("Regressions Detected: None")

    return "\n".join(lines)


def run_single_check(args: argparse.Namespace) -> Tuple[Dict[str, Any], int]:
    """Execute one full health check cycle, persist report, and print output."""
    now = utc_now()
    output_dir = Path(args.output_dir)
    prev_report = load_previous_report(output_dir)

    collected = collect_node_data(args.rpc_url, args.metrics_url, args.timeout)
    checks = evaluate_checks(collected, prev_report, now, args)
    overall_status = compute_overall_status(checks)
    regressions = detect_regressions(
        prev_report=prev_report,
        curr_status=overall_status,
        curr_metrics=collected["metrics"],
        curr_rpc_reachable=collected["rpc_reachable"],
        now=now,
        args=args,
    )

    report = {
        "timestamp": format_iso_utc(now),
        "overall_status": overall_status,
        "checks": checks,
        "metrics": collected["metrics"],
        "regressions": regressions,
    }

    report_path = save_report(output_dir, report, now)
    exit_code = determine_exit_code(overall_status, regressions)

    if args.json_output:
        print(json.dumps(report, indent=2), flush=True)
    else:
        print(format_human_summary(report, report_path), flush=True)

    return report, exit_code


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    signal.signal(signal.SIGINT, _handle_signal)
    signal.signal(signal.SIGTERM, _handle_signal)

    if args.once:
        _, exit_code = run_single_check(args)
        return exit_code

    last_exit_code = EXIT_HEALTHY
    interval = max(1, args.interval)
    while not _STOP_REQUESTED:
        _, last_exit_code = run_single_check(args)
        # Sleep in 1s increments so SIGINT/SIGTERM exits promptly
        for _ in range(interval):
            if _STOP_REQUESTED:
                break
            time.sleep(1)

    return last_exit_code


if __name__ == "__main__":
    sys.exit(main())
