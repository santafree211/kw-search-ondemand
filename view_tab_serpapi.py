"""
================================================================================
【設計メモ (Design Note)】
--------------------------------------------------------------------------------
1. モジュール概要:
   - ファイル名: view_tab_serpapi.py
   - カテゴリ: view (UI表示・操作)
   - 責務: 「SerpApi Google星数精密検証」タブのUIレイアウト構築、SerpApiキーの登録・
     設定確認、Google生SERP（上位10位）による星数の再判定と0星キーワード自動除外の実行・ログ表示。

2. 入出力・依存関係:
   - 入力: 対象性別選択（both/male/female）、検証件数上限（Limit）、SerpApiキー入力、MockMode/DryRun切替
   - 出力: Google SERPによる席数（弱競合UGC+個人ブログ）実測結果、スプレッドシート反映ログ
   - 依存先: core_config, service_runner.ProcessRunner, json, os, tkinter/ttk

3. AI改修時の指針・注意点:
   - SerpApiの月間無料枠（250回）を保護するため、Limitのデフォルト値は小さめ（5〜7件）に保つこと。
   - キーの保存・更新は `workflow/config/serpapi_config.json` を安全に読み書きすること。
================================================================================
"""

# ==============================================================================
# 実コード (Implementation)
# ==============================================================================

import os
import json
import threading
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
from core_config import (
    SCRIPT_VERIFY_SERPAPI,
    FILE_SERPAPI_CONFIG,
    COLOR_BTN_SERPAPI,
    COLOR_SUB_BG,
    COLOR_SUB_FG,
)
from service_runner import ProcessRunner

class SerpApiTab(ttk.Frame):
    """Google SerpApi 精密星数検証タブのUIクラス"""

    def __init__(self, parent):
        super().__init__(parent, padding=10)
        self._build_ui()
        self._load_config()

    def _build_ui(self):
        # 1. SerpApi設定カード
        cfg_frame = ttk.LabelFrame(self, text="🔑 SerpApi 設定・利用枠ガード", padding=10)
        cfg_frame.pack(fill=tk.X, pady=(0, 10))

        row1 = ttk.Frame(cfg_frame)
        row1.pack(fill=tk.X, pady=2)

        ttk.Label(row1, text="SerpApi Key:", font=("Meiryo", 9)).pack(side=tk.LEFT, padx=(0, 5))
        self.entry_key = ttk.Entry(row1, width=45, show="*")
        self.entry_key.pack(side=tk.LEFT, padx=5)

        btn_save_key = ttk.Button(row1, text="キーを保存", command=self._save_api_key)
        btn_save_key.pack(side=tk.LEFT, padx=5)

        self.lbl_key_status = ttk.Label(row1, text="未確認", font=("Meiryo", 9))
        self.lbl_key_status.pack(side=tk.LEFT, padx=10)

        # 2. 検証実行パラメータ
        run_frame = ttk.LabelFrame(self, text="🎯 星数精密再判定パラメータ", padding=10)
        run_frame.pack(fill=tk.X, pady=(0, 10))

        row2 = ttk.Frame(run_frame)
        row2.pack(fill=tk.X, pady=2)

        ttk.Label(row2, text="対象ジャンル区分:").pack(side=tk.LEFT, padx=5)
        self.var_gender = tk.StringVar(value="both")
        gender_combo = ttk.Combobox(row2, textvariable=self.var_gender, values=["both", "male", "female"], state="readonly", width=8)
        gender_combo.pack(side=tk.LEFT, padx=5)

        ttk.Label(row2, text="1回あたりの検証件数 (Limit):").pack(side=tk.LEFT, padx=(15, 5))
        self.var_limit = tk.StringVar(value="7")
        spin_limit = ttk.Spinbox(row2, from_=1, to=50, textvariable=self.var_limit, width=5)
        spin_limit.pack(side=tk.LEFT, padx=5)

        self.var_dryrun = tk.BooleanVar(value=False)
        chk_dry = ttk.Checkbutton(row2, text="DryRun (スプシ書込なし)", variable=self.var_dryrun)
        chk_dry.pack(side=tk.LEFT, padx=15)

        self.var_mock = tk.BooleanVar(value=False)
        chk_mock = ttk.Checkbutton(row2, text="MockMode (API消費なしテスト)", variable=self.var_mock)
        chk_mock.pack(side=tk.LEFT, padx=5)

        # 3. アクションボタン
        btn_frame = ttk.Frame(self)
        btn_frame.pack(fill=tk.X, pady=(0, 10))

        self.btn_run_serp = tk.Button(
            btn_frame,
            text="🔍 Google SerpApi 精密星数検証を実行",
            font=("Meiryo", 10, "bold"),
            bg=COLOR_BTN_SERPAPI,
            fg="white",
            padx=16,
            pady=6,
            relief=tk.FLAT,
            command=self._start_serpapi_verification
        )
        self.btn_run_serp.pack(side=tk.LEFT)

        btn_clear = ttk.Button(btn_frame, text="ログ消去", command=self._clear_logs)
        btn_clear.pack(side=tk.RIGHT)

        # 4. 実行ログエリア
        log_frame = ttk.LabelFrame(self, text="Google SERP 席判定 & スプシ同期ログ", padding=5)
        log_frame.pack(fill=tk.BOTH, expand=True)

        self.txt_log = scrolledtext.ScrolledText(
            log_frame,
            wrap=tk.WORD,
            bg=COLOR_SUB_BG,
            fg=COLOR_SUB_FG,
            font=("Consolas", 9),
            padx=8,
            pady=8
        )
        self.txt_log.pack(fill=tk.BOTH, expand=True)

    def _load_config(self):
        """SerpApi設定を読み込み"""
        if os.path.exists(FILE_SERPAPI_CONFIG):
            try:
                with open(FILE_SERPAPI_CONFIG, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
                key = cfg.get("api_key", "").strip()
                if key:
                    self.entry_key.delete(0, tk.END)
                    self.entry_key.insert(0, key)
                    self.lbl_key_status.config(text="設定済み (Ready)", foreground="#16a34a")
                else:
                    self.lbl_key_status.config(text="未設定 (キーを入力してください)", foreground="#dc2626")
            except Exception:
                self.lbl_key_status.config(text="読取エラー", foreground="#dc2626")

    def _save_api_key(self):
        """SerpApiキーをJSONに保存"""
        key = self.entry_key.get().strip()
        if not key:
            messagebox.showwarning("警告", "APIキーを入力してください。")
            return

        cfg = {}
        if os.path.exists(FILE_SERPAPI_CONFIG):
            try:
                with open(FILE_SERPAPI_CONFIG, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
            except Exception:
                pass

        cfg["api_key"] = key
        try:
            with open(FILE_SERPAPI_CONFIG, "w", encoding="utf-8") as f:
                json.dump(cfg, f, ensure_ascii=False, indent=2)
            self.lbl_key_status.config(text="保存完了 (Ready)", foreground="#16a34a")
            messagebox.showinfo("成功", "SerpApiキーを保存しました。")
        except Exception as e:
            messagebox.showerror("エラー", f"保存に失敗しました: {str(e)}")

    def _start_serpapi_verification(self):
        """検証スクリプトの非同期実行"""
        gender = self.var_gender.get()
        limit = self.var_limit.get()
        dryrun = self.var_dryrun.get()
        mock = self.var_mock.get()

        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", SCRIPT_VERIFY_SERPAPI,
            "-Gender", gender,
            "-Limit", str(limit)
        ]
        if dryrun:
            cmd.append("-DryRun")
        if mock:
            cmd.append("-MockMode")

        self.txt_log.delete("1.0", tk.END)
        self.txt_log.insert(tk.END, f"--- [START] Google SerpApi 精密星数検証を開始: {' '.join(cmd)} ---\n")
        self.btn_run_serp.config(state=tk.DISABLED)

        def worker():
            output = ProcessRunner.run_sync(cmd)
            self.after(0, lambda: self._show_result(output))

        threading.Thread(target=worker, daemon=True).start()

    def _show_result(self, text: str):
        self.txt_log.insert(tk.END, text)
        self.txt_log.insert(tk.END, "\n--- [COMPLETED] SerpApi 検証完了 ---\n")
        self.txt_log.see(tk.END)
        self.btn_run_serp.config(state=tk.NORMAL)

    def _clear_logs(self):
        self.txt_log.delete("1.0", tk.END)
