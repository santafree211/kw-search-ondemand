"""
================================================================================
【設計メモ (Design Note)】
--------------------------------------------------------------------------------
1. モジュール概要:
   - ファイル名: view_tab_audit.py
   - カテゴリ: view (UI表示・操作)
   - 責務: 「黄金比率 & 3者突合監査」タブのUIレイアウト構築、対象プロファイル選択、
     sheet_reconcile.ps1 のバックグラウンド実行トリガー、および監査結果テキストの表示。

2. 入出力・依存関係:
   - 入力: ユーザーによるプロファイル選択（both/male/female）、実行ボタン押下
   - 出力: 3者突合（シート・ルール・生データ）および黄金比率（☆☆☆過半数）の検証結果テキスト
   - 依存先: core_config (SCRIPT_SHEET_RECONCILE, 配色), service_runner.ProcessRunner, tkinter/ttk

3. AI改修時の指針・注意点:
   - 監査タブの表示項目変更やUIデザイン改修はこのファイルのみを変更すること。
   - 監査処理（PowerShell実行）中はボタンを非活性化し、完了時に安全に戻すこと。
   - 実行自体はUIスレッドを止めないよう `threading.Thread` を用い、結果反映は `self.after(0, ...)` で行うこと。
================================================================================
"""

# ==============================================================================
# 実コード (Implementation)
# ==============================================================================

import threading
import tkinter as tk
from tkinter import ttk, scrolledtext
from core_config import (
    SCRIPT_SHEET_RECONCILE,
    COLOR_BTN_AUDIT,
    COLOR_SUB_BG,
    COLOR_SUB_FG,
)
from service_runner import ProcessRunner

class AuditTab(ttk.Frame):
    """黄金比率 & 3者突合監査タブのUIクラス"""

    def __init__(self, parent):
        super().__init__(parent, padding=10)
        self._build_ui()

    def _build_ui(self):
        # --- 操作ヘッダー ---
        top_frame = ttk.Frame(self, padding=(0, 0, 0, 10))
        top_frame.pack(fill=tk.X)

        ttk.Label(top_frame, text="対象:").pack(side=tk.LEFT, padx=5)
        self.var_audit_gender = tk.StringVar(value="both")
        gender_combo = ttk.Combobox(
            top_frame,
            textvariable=self.var_audit_gender,
            values=["both", "male", "female"],
            state="readonly",
            width=10
        )
        gender_combo.pack(side=tk.LEFT, padx=5)

        self.btn_run = tk.Button(
            top_frame,
            text="🔍 3者突合監査 & 健全性チェック実行",
            font=("Meiryo", 9, "bold"),
            bg=COLOR_BTN_AUDIT,
            fg="white",
            padx=12,
            pady=4,
            relief=tk.FLAT,
            command=self._run_audit_check
        )
        self.btn_run.pack(side=tk.LEFT, padx=10)

        # --- 監査結果表示エリア ---
        self.txt_audit = scrolledtext.ScrolledText(
            self,
            wrap=tk.WORD,
            bg=COLOR_SUB_BG,
            fg=COLOR_SUB_FG,
            font=("Consolas", 9),
            padx=8,
            pady=8
        )
        self.txt_audit.pack(fill=tk.BOTH, expand=True)

    def _run_audit_check(self):
        """非同期スレッドで3者突合監査スクリプトを実行"""
        gender = self.var_audit_gender.get()
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", SCRIPT_SHEET_RECONCILE,
            "-Profile", gender
        ]

        self.txt_audit.delete("1.0", tk.END)
        self.txt_audit.insert(tk.END, f"3者突合監査を実行中 ({gender})...\n")
        self.btn_run.config(state=tk.DISABLED)

        def worker():
            output = ProcessRunner.run_sync(cmd)
            self.after(0, lambda: self._show_result(output))

        threading.Thread(target=worker, daemon=True).start()

    def _show_result(self, text: str):
        """結果テキストの更新とボタンの再活性化"""
        self.txt_audit.delete("1.0", tk.END)
        self.txt_audit.insert(tk.END, text)
        self.btn_run.config(state=tk.NORMAL)
