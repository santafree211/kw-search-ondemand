"""
================================================================================
【設計メモ (Design Note)】
--------------------------------------------------------------------------------
1. モジュール概要:
   - ファイル名: view_tab_run.py
   - カテゴリ: view (UI表示・操作)
   - 責務: 「実行 & リアルタイム監視」タブのUIレイアウト構築、ユーザー操作、
     Ubersuggest API利用状況・朝9時リセットカウントダウンの可視化カード、
     およびパイプラインの開始・停止とコンソールログ表示。

2. 入出力・依存関係:
   - 入力: ユーザー操作（パラメータ選択、開始/停止ボタン）
   - 出力: パイプライン実行、リアルタイムログ、Ubersuggest利用進捗メーター描画
   - 依存先: core_config, service_runner.ProcessRunner, service_ubersuggest_monitor.UbersuggestMonitorService

3. AI改修時の指針・注意点:
   - Ubersuggest進捗メーターは10秒ごとに自動更新（Polling）され、手動更新ボタンでも更新可能。
   - 朝9:00 JSTリセットまでの残り時間と本日消費コール数を視覚的に分かりやすく表示すること。
================================================================================
"""

# ==============================================================================
# 実コード (Implementation)
# ==============================================================================

import os
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
from core_config import (
    SCRIPT_RUN_DAILY_PACKAGE,
    SCRIPT_RUN_PIPELINE,
    COLOR_BTN_START,
    COLOR_BTN_STOP,
    COLOR_CONSOLE_BG,
    COLOR_CONSOLE_FG,
)
from service_runner import ProcessRunner
from service_ubersuggest_monitor import UbersuggestMonitorService

class RunTab(ttk.Frame):
    """実行 & リアルタイム監視タブのUIおよびイベントハンドラ"""

    def __init__(self, parent, on_status_change):
        super().__init__(parent, padding=10)
        self.on_status_change = on_status_change
        self.runner = ProcessRunner(self._append_log, self._on_process_finish)

        self._build_ui()
        self._refresh_ubersuggest_status()
        self._schedule_periodic_refresh()

    def _build_ui(self):
        # ======================================================================
        # 1. Ubersuggest API 進捗・朝9時リセット監視カード
        # ======================================================================
        uber_frame = ttk.LabelFrame(self, text="⚡ Ubersuggest API 本日進捗・朝9時リセット枠", padding=10)
        uber_frame.pack(fill=tk.X, pady=(0, 10))

        # 上段: ステータス概要
        top_row = ttk.Frame(uber_frame)
        top_row.pack(fill=tk.X, pady=(0, 5))

        self.lbl_uber_status = ttk.Label(
            top_row,
            text="接続: 確認中...",
            font=("Meiryo", 9, "bold"),
            foreground="#16a34a"
        )
        self.lbl_uber_status.pack(side=tk.LEFT, padx=(0, 20))

        self.lbl_reset_time = ttk.Label(
            top_row,
            text="⏰ 朝9時リセットまで: --",
            font=("Meiryo", 9, "bold"),
            foreground="#d97706"
        )
        self.lbl_reset_time.pack(side=tk.LEFT, padx=(0, 20))

        btn_refresh_uber = ttk.Button(top_row, text="状況を再取得", command=self._refresh_ubersuggest_status)
        btn_refresh_uber.pack(side=tk.RIGHT)

        # 中段: 進捗バーと数値
        mid_row = ttk.Frame(uber_frame)
        mid_row.pack(fill=tk.X, pady=(0, 5))

        self.lbl_calls_info = ttk.Label(
            mid_row,
            text="本日消費コール: 0 回 (基準: 09:00 JSTリセット)",
            font=("Meiryo", 9)
        )
        self.lbl_calls_info.pack(side=tk.LEFT)

        # 下段: 内訳タグ
        self.lbl_breakdown = ttk.Label(
            uber_frame,
            text="内訳: match_keywords: 0 | serp_analysis: 0 | domain: 0",
            font=("Consolas", 8),
            foreground="#475569"
        )
        self.lbl_breakdown.pack(anchor=tk.W)

        # ======================================================================
        # 2. 実行パラメータ設定エリア
        # ======================================================================
        opts_frame = ttk.LabelFrame(self, text="実行パラメータ設定", padding=10)
        opts_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(opts_frame, text="対象ジャンル区分:", font=("Meiryo", 9)).grid(row=0, column=0, sticky=tk.W, padx=5, pady=5)
        self.var_gender = tk.StringVar(value="both")
        gender_combo = ttk.Combobox(opts_frame, textvariable=self.var_gender, values=["both", "male", "female"], state="readonly", width=12)
        gender_combo.grid(row=0, column=1, sticky=tk.W, padx=5, pady=5)

        ttk.Label(opts_frame, text="実行対象:", font=("Meiryo", 9)).grid(row=0, column=2, sticky=tk.W, padx=15, pady=5)
        self.var_target = tk.StringVar(value="package")
        rb_pkg = ttk.Radiobutton(opts_frame, text="日次完全パッケージ (run_daily_package)", variable=self.var_target, value="package")
        rb_pipe = ttk.Radiobutton(opts_frame, text="探索パイプライン単体 (run_pipeline)", variable=self.var_target, value="pipeline")
        rb_pkg.grid(row=0, column=3, sticky=tk.W, padx=5)
        rb_pipe.grid(row=0, column=4, sticky=tk.W, padx=5)

        self.var_dryrun = tk.BooleanVar(value=False)
        chk_dry = ttk.Checkbutton(opts_frame, text="DryRun (API・スプシ書込なしでシミュレーション)", variable=self.var_dryrun)
        chk_dry.grid(row=1, column=1, columnspan=2, sticky=tk.W, padx=5, pady=5)

        self.var_skipaudit = tk.BooleanVar(value=False)
        chk_audit = ttk.Checkbutton(opts_frame, text="事後監査をスキップ", variable=self.var_skipaudit)
        chk_audit.grid(row=1, column=3, columnspan=2, sticky=tk.W, padx=5, pady=5)

        # ======================================================================
        # 3. アクションボタン
        # ======================================================================
        btn_frame = ttk.Frame(self)
        btn_frame.pack(fill=tk.X, pady=(0, 10))

        self.btn_start = tk.Button(
            btn_frame,
            text="▶ パイプライン実行開始",
            font=("Meiryo", 10, "bold"),
            bg=COLOR_BTN_START,
            fg="white",
            activebackground="#15803d",
            activeforeground="white",
            padx=16,
            pady=6,
            relief=tk.FLAT,
            command=self._start_pipeline
        )
        self.btn_start.pack(side=tk.LEFT, padx=(0, 10))

        self.btn_stop = tk.Button(
            btn_frame,
            text="⏹ 停止 (Kill)",
            font=("Meiryo", 10, "bold"),
            bg=COLOR_BTN_STOP,
            fg="white",
            activebackground="#b91c1c",
            activeforeground="white",
            padx=16,
            pady=6,
            relief=tk.FLAT,
            state=tk.DISABLED,
            command=self._stop_pipeline
        )
        self.btn_stop.pack(side=tk.LEFT)

        btn_clear = ttk.Button(btn_frame, text="ログ消去", command=self._clear_logs)
        btn_clear.pack(side=tk.RIGHT)

        # ======================================================================
        # 4. リアルタイムコンソールログ
        # ======================================================================
        console_frame = ttk.LabelFrame(self, text="リアルタイム実行ログ", padding=5)
        console_frame.pack(fill=tk.BOTH, expand=True)

        self.txt_console = scrolledtext.ScrolledText(
            console_frame,
            wrap=tk.WORD,
            bg=COLOR_CONSOLE_BG,
            fg=COLOR_CONSOLE_FG,
            insertbackground="white",
            font=("Consolas", 9),
            padx=8,
            pady=8
        )
        self.txt_console.pack(fill=tk.BOTH, expand=True)

    def _refresh_ubersuggest_status(self):
        """Ubersuggest APIの進捗状況を更新"""
        info = UbersuggestMonitorService.get_status()
        self.lbl_uber_status.config(
            text=f"API認証: {info['token_status']}",
            foreground="#16a34a" if info["is_token_valid"] else "#dc2626"
        )
        self.lbl_reset_time.config(
            text=f"⏰ 朝9時リセットまで: {info['time_until_reset']} (次回: {info['next_reset_jst']})"
        )
        self.lbl_calls_info.config(
            text=f"本日消費コール数: {info['calls_today']} 回 [利用枠: {info['window_start_jst']} ～]"
        )
        bd = info["breakdown"]
        self.lbl_breakdown.config(
            text=f"内訳: match_kw: {bd['match_keywords']} | serp: {bd['serp_analysis']} | domain: {bd['domain_keywords']} | other: {bd['other']}"
        )

    def _schedule_periodic_refresh(self):
        """10秒ごとに進捗・カウントダウンを自動更新"""
        self._refresh_ubersuggest_status()
        self.after(10000, self._schedule_periodic_refresh)

    def _start_pipeline(self):
        """パイプライン実行開始処理"""
        if self.runner.is_running():
            messagebox.showwarning("警告", "現在パイプラインが実行中です。")
            return

        gender = self.var_gender.get()
        target = self.var_target.get()
        dryrun = self.var_dryrun.get()
        skipaudit = self.var_skipaudit.get()

        script_path = SCRIPT_RUN_DAILY_PACKAGE if target == "package" else SCRIPT_RUN_PIPELINE
        cmd = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", script_path,
            "-Gender", gender
        ]
        if dryrun:
            cmd.append("-DryRun")
        if skipaudit and target == "package":
            cmd.append("-SkipAudit")

        self.btn_start.config(state=tk.DISABLED, bg="#9ca3af")
        self.btn_stop.config(state=tk.NORMAL)
        self.on_status_change(True)

        self._append_log(f"--- [START] コマンド起動: {' '.join(cmd)} ---\n")
        self.runner.start(cmd)

    def _stop_pipeline(self):
        """ユーザーによる安全な強制終了"""
        if self.runner.is_running():
            if messagebox.askyesno("確認", "実行中のパイプラインを強制終了しますか？"):
                self.runner.stop()
                self._reset_ui_state()

    def _on_process_finish(self, rc: int):
        """プロセス終了時のコールバック"""
        self._append_log(f"\n--- [COMPLETED] 処理終了 (終了コード: {rc}) ---\n")
        self._reset_ui_state()
        self._refresh_ubersuggest_status()

    def _reset_ui_state(self):
        """UIコンポーネントを待機中状態に復帰"""
        self.btn_start.config(state=tk.NORMAL, bg=COLOR_BTN_START)
        self.btn_stop.config(state=tk.DISABLED)
        self.on_status_change(False)

    def _append_log(self, text: str):
        """UIスレッドにログ書き込みをスケジューリング"""
        self.after(0, lambda: self._safe_insert(text))

    def _safe_insert(self, text: str):
        self.txt_console.insert(tk.END, text)
        self.txt_console.see(tk.END)

    def _clear_logs(self):
        self.txt_console.delete("1.0", tk.END)
