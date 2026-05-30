#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fetch_table_schema.py
从 MySQL 数据库获取表结构信息，输出 JSON 格式。
优先使用 pymysql 连接，不可用时回退到 mysql CLI 命令。
"""

import argparse
import json
import subprocess
import sys


def parse_args():
    parser = argparse.ArgumentParser(description="Fetch MySQL table schema")
    parser.add_argument("--host", default="localhost", help="MySQL host")
    parser.add_argument("--port", type=int, default=3306, help="MySQL port")
    parser.add_argument("--user", default="root", help="MySQL user")
    parser.add_argument("--password", default="", help="MySQL password")
    parser.add_argument("--database", required=True, help="Database name")
    parser.add_argument("--table", required=True, help="Table name")
    parser.add_argument("--skip-ssl", action="store_true", help="Skip SSL verification")
    return parser.parse_args()


def normalize_type(col_type: str) -> str:
    """统一类型字符串，去除多余空格和大小写差异"""
    return col_type.strip().lower()


def build_column(name: str, col_type: str, nullable: str, key: str) -> dict:
    return {
        "name": name,
        "type": normalize_type(col_type),
        "nullable": nullable.upper() == "YES",
        "key": key or "",
    }


# ---------------------------------------------------------------------------
# 方式一：pymysql
# ---------------------------------------------------------------------------


def fetch_via_pymysql(args):
    import pymysql  # noqa: delay import

    ssl = None
    if args.skip_ssl:
        ssl = {"ssl": {"ssl_disabled": True}}

    connect_kwargs = dict(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        database=args.database,
        charset="utf8mb4",
        connect_timeout=10,
    )
    if args.skip_ssl:
        # pymysql 使用 ssl_disabled 参数
        connect_kwargs["ssl_disabled"] = True

    conn = pymysql.connect(**connect_kwargs)
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY
                FROM INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = %s AND TABLE_NAME = %s
                ORDER BY ORDINAL_POSITION
                """,
                (args.database, args.table),
            )
            rows = cursor.fetchall()
    finally:
        conn.close()

    if not rows:
        raise RuntimeError(f"Table '{args.table}' not found or has no columns in database '{args.database}'")

    columns = [build_column(r[0], r[1], r[2], r[3]) for r in rows]
    return {"table_name": args.table, "columns": columns}


# ---------------------------------------------------------------------------
# 方式二：mysql CLI
# ---------------------------------------------------------------------------


def fetch_via_cli(args):
    cmd = [
        "mysql",
        "-h", args.host,
        "-P", str(args.port),
        "-u", args.user,
        "--batch",
        "--skip-column-names",
        "-e",
        (
            f"SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY "
            f"FROM INFORMATION_SCHEMA.COLUMNS "
            f"WHERE TABLE_SCHEMA = '{args.database}' AND TABLE_NAME = '{args.table}' "
            f"ORDER BY ORDINAL_POSITION"
        ),
        args.database,
    ]

    if args.password:
        cmd.insert(cmd.index("-u") + 2, f"-p{args.password}")

    if args.skip_ssl:
        cmd.append("--ssl-mode=DISABLED")

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

    if result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(f"mysql CLI error: {stderr}")

    lines = result.stdout.strip().splitlines()
    if not lines:
        raise RuntimeError(f"Table '{args.table}' not found or has no columns in database '{args.database}'")

    columns = []
    for line in lines:
        parts = line.split("\t")
        if len(parts) >= 4:
            columns.append(build_column(parts[0], parts[1], parts[2], parts[3]))
        elif len(parts) == 3:
            columns.append(build_column(parts[0], parts[1], parts[2], ""))

    return {"table_name": args.table, "columns": columns}


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main():
    args = parse_args()

    # 优先 pymysql，不可用时回退 CLI
    try:
        import pymysql  # noqa: F401

        result = fetch_via_pymysql(args)
    except ImportError:
        try:
            result = fetch_via_cli(args)
        except Exception as e:
            json.dump({"error": str(e)}, sys.stdout, ensure_ascii=False)
            sys.exit(1)
    except Exception as e:
        json.dump({"error": str(e)}, sys.stdout, ensure_ascii=False)
        sys.exit(1)

    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
