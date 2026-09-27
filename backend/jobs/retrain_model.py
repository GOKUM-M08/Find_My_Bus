"""Stub retraining module for continuous training architecture."""

from __future__ import annotations

import logging
from typing import Any, Optional
from database import supabase

logger = logging.getLogger("uvicorn")

MINIMUM_MONTHS_REQUIRED = 6


def check_and_trigger_model_retraining(school_id: Optional[str] = None) -> dict[str, Any]:
    """
    Checks collected monthly_analytics_snapshots and logs retraining status.
    Currently acts as a stub indicating insufficient data until >= 6 months of snapshots accumulate.
    """
    try:
        query = supabase.table("monthly_analytics_snapshots").select("id, snapshot_month")
        if school_id:
            query = query.eq("school_id", school_id)
        snapshots = query.execute().data or []

        collected_months = len(snapshots)

        if collected_months < MINIMUM_MONTHS_REQUIRED:
            msg = (
                f"Insufficient historical data to train ML model. {collected_months} month(s) collected so far "
                f"(minimum {MINIMUM_MONTHS_REQUIRED} months required). Pipeline is fully scaffolded and ready for "
                f"model training once real outcome data accumulates."
            )
            logger.info(f"[Continuous Retraining Stub] {msg}")
            return {
                "status": "insufficient_data",
                "collected_months": collected_months,
                "required_months": MINIMUM_MONTHS_REQUIRED,
                "message": msg,
            }
        else:
            msg = f"Data threshold met ({collected_months} months). Pluggable training architecture ready to execute model training."
            logger.info(f"[Continuous Retraining Stub] {msg}")
            return {
                "status": "ready_for_training",
                "collected_months": collected_months,
                "message": msg,
            }
    except Exception as e:
        logger.error(f"[Continuous Retraining Error] {e}")
        return {"status": "error", "message": str(e)}


if __name__ == "__main__":
    check_and_trigger_model_retraining()
