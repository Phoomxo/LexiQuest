import json
import time
from pathlib import Path

from lexiquest_voice.config import Settings
from lexiquest_voice.engines.omnivoice_engine import OmniVoiceEngine
from lexiquest_voice.models import SpeechRequest

RESEARCH_DIR = Path(__file__).parent
GOLDEN_SET_PATH = RESEARCH_DIR / "golden_texts.json"
OUTPUT_DIR = RESEARCH_DIR / "out"


def main() -> None:
    if not GOLDEN_SET_PATH.exists():
        print(f"Golden set dataset not found at {GOLDEN_SET_PATH}")
        return

    with GOLDEN_SET_PATH.open("r", encoding="utf-8") as f:
        items = json.load(f)

    settings = Settings()
    print(f"Loaded {len(items)} golden set items. Initializing engine with model {settings.model_id}...")

    # Initialize engine
    engine = OmniVoiceEngine(settings=settings)

    results = []
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for item in items:
        request = SpeechRequest(
            text=item["text"],
            language=item["language"],
            voice="teacher_female",
            speed=1.0,
        )

        start = time.perf_counter()
        try:
            audio = engine.synthesize(request)
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            status = "success"
            bytes_count = len(audio.data)
        except Exception as err:
            elapsed_ms = (time.perf_counter() - start) * 1000.0
            status = f"error: {err}"
            bytes_count = 0

        record = {
            "id": item["id"],
            "language": item["language"],
            "category": item["category"],
            "status": status,
            "latencyMs": round(elapsed_ms, 2),
            "audioBytes": bytes_count,
        }
        results.append(record)
        print(f"[{record['id']}] {record['status']} in {record['latencyMs']}ms ({record['audioBytes']} bytes)")

    out_file = OUTPUT_DIR / "golden_run_results.json"
    with out_file.open("w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    print(f"Golden set benchmark completed. Results saved to {out_file}")


if __name__ == "__main__":
    main()
