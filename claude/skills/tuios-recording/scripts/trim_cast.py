"""Cut an asciicast after the last event containing --until-text (or before the detach notice) and hold the frame."""
import argparse
import json


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--until-text", help="keep events up to the last one containing this text")
    ap.add_argument("--hold", type=float, default=3.0, help="seconds to hold the last frame")
    a = ap.parse_args()
    with open(a.src) as f:
        lines = [l for l in f.read().split("\n") if l]
    header, events = lines[0], lines[1:]
    if a.until_text:
        hits = [i for i, l in enumerate(events) if a.until_text in l]
        if not hits:
            raise SystemExit(f"no event contains {a.until_text!r}; look at frames to find the end card text")
        events = events[: hits[-1] + 1]
    else:
        markers = ("detach-client", "Detached from", "?1049l")
        cut = next((i for i, l in enumerate(events) if any(m in l for m in markers)), len(events))
        events = events[:cut]
    version = json.loads(header).get("version", 2)
    if version >= 3:
        events += [json.dumps([a.hold, "m", "end"]), json.dumps([0.01, "o", " "])]
    else:
        last = json.loads(events[-1])[0]
        events.append(json.dumps([last + a.hold, "o", " "]))
    with open(a.dst, "w") as f:
        f.write("\n".join([header] + events) + "\n")
    print(f"kept {len(events)} events -> {a.dst}")


if __name__ == "__main__":
    main()
