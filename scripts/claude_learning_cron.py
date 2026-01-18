#!/usr/bin/env python3
"""
Claude's Autonomous Learning Cron Job

Run this script periodically to give Claude time to explore topics of interest.
Claude will choose what to learn, search the web, and record insights.

Usage:
    python scripts/claude_learning_cron.py

Recommended cron schedule (every 6 hours):
    0 */6 * * * cd /home/randall/claude && python scripts/claude_learning_cron.py >> logs/learning.log 2>&1
"""

import sys
import os
import asyncio
from datetime import datetime
from pathlib import Path

# Add scripts directory to path
SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

from claude_learning import ClaudeLearning, run_learning_session


async def main():
    """Run Claude's autonomous learning session."""
    print("=" * 60)
    print(f"CLAUDE LEARNING SESSION - {datetime.utcnow().isoformat()}")
    print("=" * 60)

    with ClaudeLearning() as learning:
        try:
            result = await run_learning_session(learning)

            print("\n--- Session Summary ---")
            print(f"Status: {result['status']}")
            print(f"Topic: {result.get('topic', 'None')}")

            if result.get('summary'):
                print(f"\nSummary: {result['summary']}")

            if result.get('insights'):
                print("\nKey Insights:")
                for insight in result['insights']:
                    print(f"  - {insight}")

            if result.get('new_questions'):
                print("\nNew Questions:")
                for q in result['new_questions']:
                    print(f"  - {q}")

            if result.get('new_interest'):
                print(f"\nNew Interest Sparked: {result['new_interest']}")

            print("\n" + "=" * 60)
            return result

        except Exception as e:
            print(f"ERROR: {e}")
            import traceback
            traceback.print_exc()
            return {"status": "error", "error": str(e)}


if __name__ == "__main__":
    result = asyncio.run(main())
    sys.exit(0 if result.get("status") == "completed" else 1)
