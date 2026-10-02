"""
================================================================================
【設計メモ (Design Note)】
--------------------------------------------------------------------------------
1. モジュール概要:
   - ファイル名: core_logger.py
   - カテゴリ: core (ロギング基盤)
   - 責務: アプリケーション全体のエラー・トレースバックの標準化出力、ログファイル保存、
     およびAIが即座に原因特定できるように「発生ファイル名・行番号・関数名・コールスタック」
     を整形して出力する。

2. 入出力・依存関係:
   - 入力: ログメッセージ、Exceptionオブジェクト、ログレベル
   - 出力: フォーマット済みログ文字列（UI画面および `logs/app_YYYYMMDD.log` へ書き込み）
   - 依存先: core_config.APP_ROOT, logging, traceback, sys, os, datetime

3. AI改修時の指針・注意点:
   - 例外発生時は `format_exception(e)` を通すことで、AIが最も欲しがる
     「どのファイルの何行目で落ちたか」を100%確実にログに残すこと。
================================================================================
"""

# ==============================================================================
# 実コード (Implementation)
# ==============================================================================

import os
import sys
import logging
import traceback
from datetime import datetime
from typing import Optional
from core_config import APP_ROOT

LOGS_DIR = os.path.join(APP_ROOT, "logs")
if not os.path.exists(LOGS_DIR):
    os.makedirs(LOGS_DIR, exist_ok=True)

today_str = datetime.now().strftime("%Y%m%d")
LOG_FILE = os.path.join(LOGS_DIR, f"app_{today_str}.log")

# Python標準ロガーの初期化
logger = logging.getLogger("KWSearchOnDemand")
logger.setLevel(logging.DEBUG)

if not logger.handlers:
    # ファイル出力ハンドラ
    fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    file_formatter = logging.Formatter(
        "[%(asctime)s] [%(levelname)s] [%(filename)s:%(lineno)d (%(funcName)s)] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )
    fh.setFormatter(file_formatter)
    logger.addHandler(fh)

class AppLogger:
    """AI解析特化型 強化ロガークラス"""

    @staticmethod
    def info(msg: str):
        logger.info(msg)

    @staticmethod
    def warn(msg: str):
        logger.warning(msg)

    @staticmethod
    def error(msg: str, exc: Optional[Exception] = None) -> str:
        """
        エラー発生時のファイル名・行番号・スタックトレースを整形。
        UIおよびログファイルの両方に完全な追跡情報を送出する。
        """
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        detail_lines = [
            f"\n{'='*70}",
            f"❌ [CRITICAL ERROR DETECTED] {ts}",
            f"{'='*70}",
            f"■ メッセージ: {msg}"
        ]

        if exc:
            tb = exc.__traceback__
            extracted = traceback.extract_tb(tb)
            if extracted:
                last_frame = extracted[-1]
                detail_lines.append(f"■ 発生ファイル: {last_frame.filename}")
                detail_lines.append(f"■ 発生行番号  : {last_frame.lineno} 行目")
                detail_lines.append(f"■ 発生関数名  : {last_frame.name}")
                detail_lines.append(f"■ エラーコード: {last_frame.line}")
            detail_lines.append(f"■ エラー詳細  : {type(exc).__name__}: {str(exc)}")
            detail_lines.append("\n▼ 完全なコールスタック (Traceback for AI):")
            detail_lines.append(traceback.format_exc().strip())
        else:
            # 呼び出し元のフレーム情報を取得
            caller = sys._getframe(1)
            detail_lines.append(f"■ 検出元ファイル: {caller.f_code.co_filename}")
            detail_lines.append(f"■ 検出行番号    : {caller.f_lineno} 行目")
            detail_lines.append(f"■ 検出関数名    : {caller.f_code.co_name}")

        detail_lines.append(f"{'='*70}\n")
        formatted = "\n".join(detail_lines)

        logger.error(formatted)
        return formatted
