"""
================================================================================
【設計メモ (Design Note)】
--------------------------------------------------------------------------------
1. モジュール概要:
   - ファイル名: service_runner.py
   - カテゴリ: service (業務・ロジック処理)
   - 責務: バックグラウンドでのサブプロセス（PowerShell等）の起動、リアルタイム標準出力
     のストリーミング購読、Windowsタスクツリーの安全な強制終了（Kill）、
     およびcore_loggerを通じたファイル名・行番号付き例外ハンドリング。

2. 入出力・依存関係:
   - 入力: 実行コマンド配列（cmd: List[str]）、コールバック関数（log_callback, finish_callback）
   - 出力: リアルタイム標準出力ログ、終了コード（rc: int）、同期実行時の全文字列
   - 依存先: core_config.BASE_DIR, core_logger.AppLogger, subprocess, threading, typing

3. AI改修時の指針・注意点:
   - サブプロセス起動やスレッド内部で例外が起きた際は、必ず `AppLogger.error()` を通して
     「どのファイルの何行目で落ちたか」をログとUIに完全出力すること。
   - PowerShell側のスタックトレース出力（PowerShell Error Record）をそのまま透過して画面に流すこと。
================================================================================
"""

# ==============================================================================
# 実コード (Implementation)
# ==============================================================================

import subprocess
import threading
from typing import Callable, List, Optional
from core_config import BASE_DIR
from core_logger import AppLogger

class ProcessRunner:
    """サブプロセスの非同期実行およびライフサイクル管理クラス"""

    def __init__(self, log_callback: Callable[[str], None], finish_callback: Callable[[int], None]):
        self.log_callback = log_callback
        self.finish_callback = finish_callback
        self.running_process: Optional[subprocess.Popen] = None
        self._is_killed = False

    def is_running(self) -> bool:
        """プロセスが現在実行中かを判定"""
        return self.running_process is not None and self.running_process.poll() is None

    def start(self, cmd: List[str]) -> bool:
        """非同期スレッドを起動し、コマンドを実行してログを逐次送信"""
        if self.is_running():
            return False

        self._is_killed = False

        def worker():
            rc = 1
            try:
                AppLogger.info(f"Subprocess started: {' '.join(cmd)}")
                self.running_process = subprocess.Popen(
                    cmd,
                    cwd=BASE_DIR,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    bufsize=1
                )
                for line in self.running_process.stdout:
                    self.log_callback(line)

                self.running_process.wait()
                rc = self.running_process.returncode
                AppLogger.info(f"Subprocess exited with code: {rc}")
            except Exception as e:
                err_report = AppLogger.error("バックグラウンド実行中に致命的エラーが発生しました", e)
                self.log_callback(err_report)
            finally:
                self.running_process = None
                self.finish_callback(rc)

        threading.Thread(target=worker, daemon=True).start()
        return True

    def stop(self) -> bool:
        """実行中のプロセスツリーを安全かつ強制的に終了"""
        if not self.is_running():
            return False

        self._is_killed = True
        try:
            pid = self.running_process.pid
            AppLogger.info(f"Killing process tree for PID: {pid}")
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True)
            self.log_callback("\n--- [STOPPED] ユーザー指示によりプロセスを強制終了しました ---\n")
            self.running_process = None
            return True
        except Exception as e:
            err_report = AppLogger.error("プロセスの強制終了中にエラーが発生しました", e)
            self.log_callback(err_report)
            return False

    @staticmethod
    def run_sync(cmd: List[str]) -> str:
        """同期コマンド実行（単発の監査や水位レポート取得用）"""
        try:
            AppLogger.info(f"Sync command started: {' '.join(cmd)}")
            res = subprocess.run(cmd, cwd=BASE_DIR, capture_output=True, text=True, encoding="utf-8", errors="replace")
            output = res.stdout if res.stdout else res.stderr
            AppLogger.info(f"Sync command finished with code: {res.returncode}")
            return output
        except Exception as e:
            err_report = AppLogger.error("同期コマンド実行中にエラーが発生しました", e)
            return err_report
