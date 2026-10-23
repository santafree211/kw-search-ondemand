"""
================================================================================
【設計メモ (Design Note)】
--------------------------------------------------------------------------------
1. モジュール概要:
   - ファイル名: service_ubersuggest_monitor.py
   - カテゴリ: service (モニタリングサービス)
   - 責務: Ubersuggest APIの利用進捗、朝9時リセット枠の監視。
     完全ポータブル対応（%USERPROFILE% 動的解決、ローカル設定ファイル優先）。

2. 入出力・依存関係:
   - 入力: なし
   - 出力: Ubersuggest利用状況サマリー辞書 (dict)
   - 依存先: core_config.BASE_DIR, SQLite, os, json, datetime

3. AI改修時の指針・注意点:
   - ユーザー名（C:\\Users\\santa 等）のハードコードは厳禁。必ず動的解決関数 `get_tokens_file_path()`
     を介してトークンファイルを参照すること。
================================================================================
"""

# ==============================================================================
# 実コード (Implementation)
# ==============================================================================

import os
import json
import sqlite3
from datetime import datetime, timedelta
from typing import Dict, Any
from core_config import BASE_DIR, APP_ROOT

def get_tokens_file_path() -> str:
    """ポータブルなトークンファイル解決ロジック"""
    # 1. アプリローカルの config/mcp_oauth_tokens.json を最優先
    local_path = os.path.join(APP_ROOT, "config", "mcp_oauth_tokens.json")
    if os.path.exists(local_path):
        return local_path
    
    # 2. kw-serch 直下の config/mcp_oauth_tokens.json
    kw_path = os.path.join(BASE_DIR, "workflow", "config", "mcp_oauth_tokens.json")
    if os.path.exists(kw_path):
        return kw_path

    # 3. ユーザープロファイルディレクトリ (Windows標準環境変数)
    user_profile = os.environ.get("USERPROFILE", "")
    if user_profile:
        user_path = os.path.join(user_profile, ".gemini", "antigravity", "mcp_oauth_tokens.json")
        if os.path.exists(user_path):
            return user_path

    return local_path

RESEARCH_DB = os.path.join(BASE_DIR, "workflow", "data", "research.db")

class UbersuggestMonitorService:
    """Ubersuggest APIの進捗・朝9時リセット枠を監視するサービス"""

    @staticmethod
    def get_status(daily_quota_limit: int = 100) -> Dict[str, Any]:
        now = datetime.now()

        # 09:00 JST 境界線計算
        if now.hour < 9:
            window_start = datetime(now.year, now.month, now.day, 9, 0, 0) - timedelta(days=1)
            next_reset = datetime(now.year, now.month, now.day, 9, 0, 0)
        else:
            window_start = datetime(now.year, now.month, now.day, 9, 0, 0)
            next_reset = datetime(now.year, now.month, now.day, 9, 0, 0) + timedelta(days=1)

        remain_seconds = max(0, int((next_reset - now).total_seconds()))
        rem_hours = remain_seconds // 3600
        rem_mins = (remain_seconds % 3600) // 60

        tokens_file = get_tokens_file_path()
        token_status = "未設定"
        is_token_valid = False
        if os.path.exists(tokens_file):
            try:
                with open(tokens_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                entry = data.get("https://ubersuggest-mcp.neilpatelapi.com/mcp", {})
                token_obj = entry.get("token", {})
                if token_obj.get("access_token"):
                    token_status = "認証済み (ONLINE)"
                    is_token_valid = True
                else:
                    token_status = "トークンなし"
            except Exception:
                token_status = "読取エラー"

        # SQLiteから本日（朝9時以降）の実コール数集計
        calls_today = 0
        breakdown = {
            "serp_analysis": 0,
            "match_keywords": 0,
            "domain_keywords": 0,
            "keyword_overview": 0,
            "other": 0
        }

        if os.path.exists(RESEARCH_DB):
            try:
                conn = sqlite3.connect(RESEARCH_DB)
                cur = conn.cursor()
                iso_start = window_start.strftime("%Y-%m-%dT%H:%M:%S")
                cur.execute(
                    "SELECT endpoint, COUNT(*) FROM api_call_logs WHERE timestamp >= ? GROUP BY endpoint;",
                    (iso_start,)
                )
                rows = cur.fetchall()
                for ep, cnt in rows:
                    if ep in breakdown:
                        breakdown[ep] = cnt
                    else:
                        breakdown["other"] += cnt
                    calls_today += cnt
                conn.close()
            except Exception:
                pass

        remaining_calls = max(0, daily_quota_limit - calls_today)

        return {
            "is_token_valid": is_token_valid,
            "token_status": token_status,
            "calls_today": calls_today,
            "daily_quota_limit": daily_quota_limit,
            "remaining_calls": remaining_calls,
            "window_start_jst": window_start.strftime("%Y-%m-%d 09:00"),
            "next_reset_jst": next_reset.strftime("%Y-%m-%d 09:00"),
            "time_until_reset": f"{rem_hours}時間 {rem_mins}分",
            "breakdown": breakdown,
            "tokens_source": tokens_file
        }
