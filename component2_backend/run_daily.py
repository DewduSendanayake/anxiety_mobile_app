from __future__ import annotations

import asyncio
import json

from processor import Component2Processor


async def main() -> None:
    processor = Component2Processor.from_env()
    try:
        results = await processor.process_all()
        print(json.dumps(results, indent=2))
    finally:
        await processor.db.close()


if __name__ == "__main__":
    asyncio.run(main())
