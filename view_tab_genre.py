"""
================================================================================
【設計メモ (Design Note)】
--------------------------------------------------------------------------------
1. モジュール概要:
   - ファイル名: view_tab_genre.py
   - カテゴリ: view (UI表示・操作)
   - 責務: 「50ジャンル水位進捗」タブのUIレイアウト構築、対象プロファイル（male/female）選択、
     genre_inspect.ps1 のバックグラウンド実行トリガー、および水位・残KW状況テキストの表示。

2. 入出力・依存関係:
   - 入力: ユーザーによるプロファイル選択（male/female）、更新ボタン押下
   - 出力: 50ジャンルの現在の登録キーワード数、目標（200件）への進捗、不足ジャンル一覧
   - 依存先: core_config (SCRIPT_GENRE_INSPECT, 配色), service_runner.ProcessRunner, tkinter/ttk

3. AI改修時の指針・注意点:
   - 水位表示画面のレイアウトやフォント、色を変更する場合はこのファイルのみを修正すること。
   - バックグラウンド実行時はボタンを非活性化して二重起動を防止すること。
   - レポート取得結果の描画は、必ず `self.after(0, ...)` でUIスレッドに委譲すること。
================================================================================
"""

# ==============================================================================
# 実コード (Implementation)
# ==============================================================================

import threading
import tkinter as tk
from tkinter import ttk, scrolledtext
from core_config import (
    SCRIPT_GENRE_INSPECT,
    COLOR_BTN_GENRE,
    COLOR_SUB_BG,
    COLOR_SUB_FG,
)
from service_runner import ProcessRunner

class GenreTab(ttk.Frame):
    """50ジャンル水位進捗タブのUIクラス"""

    def __init__(self, parent):
        super().__init__(parent, padding=10)
        self._build_ui()

    def _build_ui(self):
        # --- 操作ヘッダー ---
        top_frame = ttk.Frame(self, padding=(0, 0, 0, 10))
        top_frame.pack(fill=tk.X)

        ttk.Label(top_frame, text="プロファイル:").pack(side=tk.LEFT, padx=5)
        self.var_genre_gender = tk.StringVar(value="male")
        gender_combo = ttk.Combobox(
            top_frame,
            textvariable=self.var_genre_gender,
            values=["male", "female"],
            state="readonly",
            width=10
        )
        gender_combo.pack(side=tk.LEFT, padx=5)

        self.btn_run = tk.Button(
            top_frame,
            text="📈 水位 & 残KW状況を更新",
            font=("Meiryo", 9, "bold"),
            bg=COLOR_BTN_GENRE,
            fg="white",
            padx=12,
            pady=4,
            relief=tk.FLAT,
            command=self._run_genre_inspect
        )
        self.btn_run.pack(side=tk.LEFT, padx=10)

        # --- 水位結果表示エリア ---
        self.txt_genre = scrolledtext.ScrolledText(
            self,
            wrap=tk.WORD,
            bg=COLOR_SUB_BG,
            fg=COLOR_SUB_FG,
            font=("Consolas", 9),
            padx=8,
            pady=8
        )
        self.txt_genre.pack(fill=tk.BOTH, expand=True)

    def _run_genre_inspect(self):
        """非同期スレッドで50ジャンル水位スクリプトを実行"""
        gender = self.var_genre_gender.get()
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", SCRIPT_GENRE_INSPECT,
            "-Gender", gender
        ]

        self.txt_genre.delete("1.0", tk.END)
        self.txt_genre.insert(tk.END, f"50ジャンル水位レポートを取得中 ({gender})...\n")
        self.btn_run.config(state=tk.DISABLED)

        def worker():
            output = ProcessRunner.run_sync(cmd)
            self.after(0, lambda: self._show_result(output))

        threading.Thread(target=worker, daemon=True).start()

    def _show_result(self, text: str):
        """結果テキストの更新とボタンの再活性化"""
        self.txt_genre.delete("1.0", tk.END)
        self.txt_genre.insert(tk.END, text)
        self.btn_run.config(state=tk.NORMAL)
