"""
================================================================================
【設計メモ (Design Note)】
--------------------------------------------------------------------------------
1. モジュール概要:
   - ファイル名: core_config.py
   - カテゴリ: core (基盤・設定)
   - 責務: アプリケーション全体のパス解決、スクリプトパス一覧、UI定数、配色テーマの集中管理。
     SerpApi検証スクリプトおよび設定ファイルのパス定義を追加。

2. 入出力・依存関係:
   - 入力: なし (静的定数定義)
   - 出力: 各種パス変数、UI設定定数 (他全モジュールから参照される)
   - 外部依存: osモジュールのみ

3. AI改修時の指針・注意点:
   - スクリプトの追加やkw-serch側のパス構造が変わった場合は、このファイルのみを変更すること。
================================================================================
"""

# ==============================================================================
# 実コード (Implementation)
# ==============================================================================

import os

# --- パス解決 ---
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
APP_ROOT = CURRENT_DIR

# kw-serch リサーチエンジン側のベースディレクトリ
BASE_DIR = os.path.abspath(os.path.join(APP_ROOT, "..", "kw-serch"))
TOOLS_DIR = os.path.join(BASE_DIR, "tools")
WORKFLOW_CONFIG_DIR = os.path.join(BASE_DIR, "workflow", "config")

# --- 実行対象スクリプトのフルパス ---
SCRIPT_RUN_DAILY_PACKAGE = os.path.join(TOOLS_DIR, "run_daily_package.ps1")
SCRIPT_RUN_PIPELINE = os.path.join(TOOLS_DIR, "run_pipeline.ps1")
SCRIPT_SHEET_RECONCILE = os.path.join(TOOLS_DIR, "sheet_reconcile.ps1")
SCRIPT_GENRE_INSPECT = os.path.join(TOOLS_DIR, "genre_inspect.ps1")
SCRIPT_VERIFY_SERPAPI = os.path.join(TOOLS_DIR, "verify_sheet_serpapi.ps1")
SCRIPT_SETUP_SERPAPI = os.path.join(TOOLS_DIR, "setup_serpapi_key.ps1")
FILE_SERPAPI_CONFIG = os.path.join(WORKFLOW_CONFIG_DIR, "serpapi_config.json")

# --- ウィンドウ・UI共通設定 ---
APP_TITLE = "KW-Search オンデマンド自動探索コントローラー"
WINDOW_SIZE = "1020x780"
WINDOW_MIN_SIZE = (880, 620)
DEFAULT_THEME = "vista"

# --- UIカラーパレット ---
COLOR_IDLE_BG = "#e0f2fe"
COLOR_IDLE_FG = "#2563eb"
COLOR_RUNNING_BG = "#dcfce7"
COLOR_RUNNING_FG = "#16a34a"

COLOR_BTN_START = "#16a34a"
COLOR_BTN_STOP = "#dc2626"
COLOR_BTN_AUDIT = "#2563eb"
COLOR_BTN_GENRE = "#0891b2"
COLOR_BTN_SERPAPI = "#7c3aed"

COLOR_CONSOLE_BG = "#0f172a"
COLOR_CONSOLE_FG = "#f8fafc"
COLOR_SUB_BG = "#1e293b"
COLOR_SUB_FG = "#e2e8f0"
