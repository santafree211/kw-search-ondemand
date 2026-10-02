"""
================================================================================
【設計メモ (Design Note)】
--------------------------------------------------------------------------------
1. モジュール概要:
   - ファイル名: view_main_window.py
   - カテゴリ: view (UI表示・操作) / entrypoint (起動口)
   - 責務: メインウィンドウ（Tkinter Tk）の生成とライフサイクル管理、上部タイトル・
     ステータスバッジの描画、全タブのNotebook統合、および直接起動時のエントリポイント。
     新設の「Google SerpApi 精密星数検証タブ (view_tab_serpapi.py)」を統合。

2. 入出力・依存関係:
   - 入力: アプリ起動要求、各タブからの稼働ステータス変更イベント (set_running_state)
   - 出力: アプリケーション全体のGUIウィンドウ
   - 依存先: core_config, view_tab_run, view_tab_audit, view_tab_genre, view_tab_serpapi

3. AI改修時の指針・注意点:
   - 新しいタブの追加や削除はこのファイルの `_build_tabs` を保守すること。
================================================================================
"""

# ==============================================================================
# 実コード (Implementation)
# ==============================================================================

import tkinter as tk
from tkinter import ttk
from core_config import (
    APP_TITLE,
    WINDOW_SIZE,
    WINDOW_MIN_SIZE,
    DEFAULT_THEME,
    COLOR_IDLE_BG,
    COLOR_IDLE_FG,
    COLOR_RUNNING_BG,
    COLOR_RUNNING_FG,
)
from view_tab_run import RunTab
from view_tab_audit import AuditTab
from view_tab_genre import GenreTab
from view_tab_serpapi import SerpApiTab

class MainWindow(tk.Tk):
    """メインウィンドウクラス"""

    def __init__(self):
        super().__init__()
        self.title(APP_TITLE)
        self.geometry(WINDOW_SIZE)
        self.minsize(*WINDOW_MIN_SIZE)

        self.style = ttk.Style(self)
        try:
            self.style.theme_use(DEFAULT_THEME)
        except Exception:
            pass

        self._build_header()
        self._build_tabs()

    def _build_header(self):
        """上部タイトルバーおよび稼働中/待機中バッジの描画"""
        header_frame = ttk.Frame(self, padding=(12, 10))
        header_frame.pack(fill=tk.X)

        title_lbl = ttk.Label(
            header_frame,
            text="🎯 KW-Search オンデマンド自動探索コントローラー",
            font=("Meiryo", 14, "bold")
        )
        title_lbl.pack(side=tk.LEFT)

        self.status_badge = ttk.Label(
            header_frame,
            text="待機中 (IDLE)",
            font=("Meiryo", 10, "bold"),
            foreground=COLOR_IDLE_FG,
            background=COLOR_IDLE_BG,
            padding=(8, 4)
        )
        self.status_badge.pack(side=tk.RIGHT)

    def _build_tabs(self):
        """各タブコンポーネントをNotebookに登録"""
        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill=tk.BOTH, expand=True, padx=10, pady=5)

        # Tab 1: 実行 & リアルタイム監視
        self.tab_run = RunTab(self.notebook, on_status_change=self.set_running_state)
        self.notebook.add(self.tab_run, text="  🚀 実行 & リアルタイム監視  ")

        # Tab 2: 黄金比率 & 3者突合監査
        self.tab_audit = AuditTab(self.notebook)
        self.notebook.add(self.tab_audit, text="  📊 黄金比率 & 3者突合監査  ")

        # Tab 3: 50ジャンル水位進捗
        self.tab_genre = GenreTab(self.notebook)
        self.notebook.add(self.tab_genre, text="  📈 50ジャンル水位進捗  ")

        # Tab 4: Google SerpApi 精密星数検証
        self.tab_serpapi = SerpApiTab(self.notebook)
        self.notebook.add(self.tab_serpapi, text="  🔍 Google SerpApi 精密星数検証  ")

    def set_running_state(self, is_running: bool):
        """パイプライン稼働状態に応じたバッジの表示切り替え"""
        if is_running:
            self.status_badge.config(
                text="稼働中 (RUNNING)",
                foreground=COLOR_RUNNING_FG,
                background=COLOR_RUNNING_BG
            )
        else:
            self.status_badge.config(
                text="待機中 (IDLE)",
                foreground=COLOR_IDLE_FG,
                background=COLOR_IDLE_BG
            )

def launch_gui():
    """GUIアプリケーションの起動関数"""
    app = MainWindow()
    app.mainloop()

if __name__ == "__main__":
    launch_gui()
