"""Knowledge-only conversation policy. No device tools, pose or map context."""
import re

LIVE_PATTERNS = [
    r'\b(take|guide|navigate|walk|lead|bring|direct)\s+me\b',
    r'\b(go|head|turn)\s+(left|right|around|back|to|toward|towards|straight)\b',
    r'\b(get|walk|go)\s+to\b',
    r'\b(room|suite|floor|level)\s*[-#]?\s*(\d+|zero|one|two|three|four|five|six|seven|eight|nine)\b',
    r'\b(where am i|how far|how much farther|which way|nearest|closest|near me|nearby|in front|ahead of me|my location|my position|my route|my destination)\b',
    r'\b(read|scan)\s+(a |the |this )?(sign|label|text)\b',
    r"\b(what do you see|what can you see|what's ahead|what is ahead|describe (the |my )?(view|surroundings)|is it safe|can i cross)\b",
    r'\b(find|locate)\s+(the |a |an )?(exit|entrance|room|restroom|bathroom|elevator|lift)\b',
    r'^(please )?(avoid stairs|reroute|recalculate|repeat|pause|stop|mute|unmute|add |buy |start |record )',
]

def normalized(text):
    return text.lower().replace('’', "'").strip()

def is_general(text, follows_general=False):
    text = normalized(text)
    if not text or len(text) > 1000 or any(re.search(p, text) for p in LIVE_PATTERNS): return False
    if text.rstrip('.!?') in ('hi', 'hello', 'hey', 'thanks', 'thank you'): return True
    if re.search(r"^(what|what's|who|who's|why|how|when|where|is|are|can|could|would|should|do|does|did|tell me|explain|define|help me understand|give me)\b", text): return True
    if re.search(r'^[\d\s()+*/.^%−-]+[+*/.^%−-][\d\s()+*/.^%−-]+\??$', text): return True
    return follows_general and bool(re.search(r'^(and |also |more detail|a bit more|simpler|shorter|say that more simply)', text))

def accepts_answer(answer):
    text = normalized(answer)
    if not text or len(answer) > 650: return False
    patterns = [
        r'\b(turn|go|walk|head|move)\s+(left|right|straight|forward|backward|around)\b',
        r"\b(you are at|you're at|you have arrived|you've arrived|i changed your (route|destination)|i can see|i see (a|the))\b",
        r'\b(your destination|the exit|the entrance) is (on|to) (your |the )?(left|right)\b',
    ]
    return not any(re.search(p, text) for p in patterns)
