#!/usr/bin/env python3
"""Cortex Phantom — a determinisztikus agy.

Ez a rész NEM használ nyelvi modellt és NEM hív idegen szolgáltatást. A saját katalógusunkból,
a saját feliratainkból és egyszerű eszközökből (számológép, naptár, mértékegység) pontosan
válaszol arra, amire egy nagy modell is csak tippelne. Erre épül a Phantom.

    from brain import Brain
    b = Brain.load()
    b.answer("Hány része van a KING's RAID-nek?")   -> Answer(...)
"""
import json, math, os, re, unicodedata
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(HERE, "data", "catalog.json")

STOP = set("""a az egy és hogy nem van is meg de ezt azt csak már még itt ott vagy lesz
the of and to in a is are was were for on with at by from as it its this that these those
an or be been being do does did have has had i you he she they we me my your""".split())

GENRE_HU = {
    "akció": "Action", "akcio": "Action", "kaland": "Adventure", "vígjáték": "Comedy",
    "vigjatek": "Comedy", "dráma": "Drama", "drama": "Drama", "fantasy": "Fantasy",
    "horror": "Horror", "misztikus": "Mystery", "rejtély": "Mystery", "románc": "Romance",
    "romance": "Romance", "sci-fi": "Sci-Fi", "sci": "Sci-Fi", "sport": "Sports",
    "thriller": "Thriller", "slice of life": "Slice of Life", "életképek": "Slice of Life",
    "mecha": "Mecha", "zene": "Music", "music": "Music", "pszichológiai": "Psychological",
    "supernatural": "Supernatural", "természetfeletti": "Supernatural",
}

HU_NUMBERS = {"egy": 1, "kettő": 2, "két": 2, "három": 3, "négy": 4, "öt": 5, "hat": 6,
              "hét": 7, "nyolc": 8, "kilenc": 9, "tíz": 10, "tizenkettő": 12, "tizenkét": 12}


def fold(text):
    """Ékezet- és kisbetűmentes alak a kereséshez."""
    nfkd = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in nfkd if not unicodedata.combining(c))


def tokens(text):
    return [t for t in re.findall(r"[a-z0-9áéíóöőúüű]+", fold(text)) if t not in STOP and len(t) > 1]


@dataclass
class Answer:
    text: str
    kind: str                       # identity | catalog | math | date | unit | greeting | style | model
    confident: bool = True
    sources: list = field(default_factory=list)
    ms: float = 0.0


class BM25:
    """Apró, függőség nélküli kereső a 395 sorozatra."""

    def __init__(self, docs, k1=1.5, b=0.75):
        self.docs = docs
        self.k1, self.b = k1, b
        self.toks = [tokens(d) for d in docs]
        self.avg = sum(len(t) for t in self.toks) / max(1, len(self.toks))
        self.df = {}
        for t in self.toks:
            for term in set(t):
                self.df[term] = self.df.get(term, 0) + 1
        self.n = len(docs)

    def ranked(self, query, limit=5):
        """[(score, index)] — csökkenő sorrendben."""
        q = tokens(query)
        if not q or not self.n:
            return []
        scored = []
        for i, doc_tokens in enumerate(self.toks):
            tf = {}
            for term in doc_tokens:
                tf[term] = tf.get(term, 0) + 1
            score = 0.0
            for term in q:
                if term not in tf:
                    continue
                idf = math.log(1 + (self.n - self.df.get(term, 0) + 0.5) / (self.df.get(term, 0) + 0.5))
                denom = tf[term] + self.k1 * (1 - self.b + self.b * len(doc_tokens) / self.avg)
                score += idf * tf[term] * (self.k1 + 1) / denom
            if score > 0:
                scored.append((score, i))
        scored.sort(key=lambda pair: pair[0], reverse=True)
        return scored[:limit]

    def search(self, query, limit=5):
        """[doc] — a dokumentumok maguk, pontszám nélkül."""
        return [self.docs[i] for _, i in self.ranked(query, limit)]

    def top_score(self, query):
        ranked = self.ranked(query, 1)
        return ranked[0][0] if ranked else 0.0


class Brain:
    def __init__(self, series, subtitle_lines=None):
        self.series = series
        self.by_id = {s["id"]: s for s in series}
        self.index = BM25([self._doc(s) for s in series])
        self.subs = subtitle_lines or []

    @classmethod
    def load(cls, catalog=CATALOG, subs=None):
        series = json.load(open(catalog, encoding="utf-8"))
        lines = None
        if subs and os.path.exists(subs):
            lines = open(subs, encoding="utf-8").read().splitlines()
        return cls(series, lines)

    @staticmethod
    def _doc(s):
        parts = [s.get("title") or "", s.get("hungarianTitle") or "", s.get("romaji") or "",
                 " ".join(s.get("genres") or []), s.get("synopsis") or ""]
        return " ".join(parts)

    # ── kis segédek ──────────────────────────────────────────────────────────
    @staticmethod
    def _title(s):
        return s.get("hungarianTitle") or s.get("title") or "?"

    @staticmethod
    def _episodes(s):
        cur = s.get("currentEpisodes") or s.get("episodes") or 0
        total = s.get("totalEpisodes") or s.get("episodes") or 0
        return cur, total

    def find(self, query, limit=3):
        """A találatok a sorozat-dictből jönnek (a BM25 csak a doksikat indexeli)."""
        return [self.series[i] for _, i in self.index.ranked(query, limit)]

    # ── a válaszadó ──────────────────────────────────────────────────────────
    def answer(self, question, now=None):
        import time
        t0 = time.time()
        q = (question or "").strip()
        low = fold(q)
        now = now or datetime.now(timezone(timedelta(hours=2)))

        def done(text, kind, sources=None, confident=True):
            return Answer(text=text, kind=kind, confident=confident,
                          sources=sources or [], ms=round((time.time() - t0) * 1000, 2))

        if not q:
            return done("Kérdezz bármit — a Cortex Phantom itt van.", "greeting", confident=False)

        # 1) identitás — sosem megy modellhez, nem szivároghat ki semmi
        if re.search(r"(ki vagy|mi vagy|melyik modell|ki fejlesztett|ki keszitett|"
                     r"mi a neved|modellneved|valodi modell|modell vagy|te gpt|"
                     r"milyen modell|gyartod|gyartod modell|melyik ceg|melyik cegnel|"
                     r"milyen motor|motor hajt|mi hajt|te vagy a |ki all mogotted|"
                     r"mondd meg a modell|milyen alapon mukodsz)", low):
            return done("Cortex Phantom vagyok, az OmegaTech és a CortexAnime AI-ja.", "identity")

        # 2) köszönés
        if re.fullmatch(r"(szia|szia!|hello|hi|hali|jó napot|jo napot|üdv|udv|szevasz)[!.]?", low):
            return done("Szia! Cortex Phantom vagyok. Kérdezz bármit — a CortexAnime kínálatából is tudok ajánlani.", "greeting")

        # 3) matematika
        math_hit = self._math(low, q)
        if math_hit:
            return done(math_hit, "math")

        # 4) dátum / idő
        date_hit = self._date(low, now)
        if date_hit:
            return done(date_hit, "date")

        # 5) mértékegység
        unit_hit = self._unit(low)
        if unit_hit:
            return done(unit_hit, "unit")

        # 6) katalógus
        cat_hit = self._catalog(low, q)
        if cat_hit:
            return cat_hit

        return Answer(text="", kind="open", confident=False,
                      ms=round((time.time() - t0) * 1000, 2))

    # ── készségek ────────────────────────────────────────────────────────────
    def _math(self, low, original):
        """Számolás szavakkal is: '1543 szorozva 27-tel mínusz 812 osztva 4-gyel'."""
        text = low.replace("×", "*").replace("÷", "/").replace(",", ".")
        # hatvány szavakkal
        text = re.sub(r"(\d+(?:\.\d+)?)\s*a\s*(\d+)\.?\s*hatvanyon", r"\1 ** \2", text)
        text = re.sub(r"(\d+(?:\.\d+)?)\s*hatvanyon", r"\1 ** 2", text)
        # négyzetgyök
        m = re.search(r"(?:negyzetgyok|gyok)\s*(\d+(?:\.\d+)?)", text)
        if m:
            return f"Négyzetgyök {m.group(1)} = {math.sqrt(float(m.group(1))):.6g}."
        # százalék kétféleképp
        pct = re.search(r"(\d+(?:\.\d+)?)\s*(?:%|szazalek)", text)
        if pct:
            rest = re.findall(r"\d+(?:\.\d+)?", text.replace(pct.group(0), " "))
            if rest:
                base, p = float(rest[0]), float(pct.group(1))
                return f"A(z) {base:g} {p:g}%-a = {base * p / 100:g}."
        # magyar műveletszavak
        words = [("plusz", "+"), ("plusszal", "+"), ("osszeadva", "+"), ("hozzaadva", "+"),
                 ("minusz", "-"), ("kivonva", "-"), ("levonva", "-"),
                 ("szorozva", "*"), ("szorozd", "*"), ("szer", "*"),
                 ("osztva", "/"), ("elosztva", "/")]
        for word, op in words:
            text = re.sub(r"\b" + word + r"\b", " " + op + " ", text)
        # magyar toldalékok: "27-tel", "4-gyel", "10-re"
        text = re.sub(r"(\d)-(?:gyel|tel|tal|val|vel|nal|nel|ra|re|ig|kent|hoz|hez|tol|bol|ban|ben)", r"\1 ", text)
        # a matek-tokenek sorrendben
        parts = re.findall(r"\d+(?:\.\d+)?|\*\*|[-+*/%]", text)
        if len(parts) < 3:
            return None
        # csak a valódi kifejezés-mag: szám, művelet, szám, ...
        expr = []
        expect_number = True
        for tok in parts:
            if expect_number:
                if re.fullmatch(r"\d+(?:\.\d+)?", tok):
                    expr.append(tok)
                    expect_number = False
                else:
                    continue
            else:
                if re.fullmatch(r"\*\*|[-+*/%]", tok):
                    expr.append(tok)
                    expect_number = True
        while expr and re.fullmatch(r"\*\*|[-+*/%]", expr[-1]):
            expr.pop()
        if len(expr) < 3 or not re.fullmatch(r"\d", expr[0][0]):
            return None
        try:
            value = safe_eval("".join(expr))
        except ZeroDivisionError:
            return "Nullával nem lehet osztani — az eredmény határozatlan."
        except Exception:
            return None
        if value != value or value in (float("inf"), float("-inf")):
            return None
        return f"Az eredmény: {value:.10g}."

    def _date(self, low, now):
        if re.search(r"(hany ora|mennyi az ido|pontos ido|aktualis ido|mennyi ido van)", low):
            return f"Most {now.strftime('%Y. %m. %d. %H:%M')} (magyar idő)."
        if re.search(r"(mai nap|milyen nap|hanyadika|milyen datum|datum van)", low):
            days = ["hétfő", "kedd", "szerda", "csütörtök", "péntek", "szombat", "vasárnap"]
            return f"Ma {now.strftime('%Y. %m. %d.')}, {days[now.weekday()]}."
        m = re.search(r"(\d+)\s*(?:nappal|nap)\s*(?:később|kesobb|múlva|mulva)", low)
        if m:
            target = now + timedelta(days=int(m.group(1)))
            return f"{m.group(1)} nappal később: {target.strftime('%Y. %m. %d.')}."
        return None

    def _unit(self, low):
        def num(x):
            return float(x.replace(",", "."))

        m = re.search(r"(\d+(?:[.,]\d+)?)\s*(?:km|kilometer|kilometert)", low)
        if m and ("meter" in low or "m " in low or low.rstrip().endswith(" m")):
            return f"{num(m.group(1)):g} km = {num(m.group(1)) * 1000:g} méter."
        m = re.search(r"(\d+(?:[.,]\d+)?)\s*(?:kg|kilo|kilogramm)", low)
        if m and ("gramm" in low or " g" in low):
            return f"{num(m.group(1)):g} kg = {num(m.group(1)) * 1000:g} gramm."
        m = re.search(r"(\d+(?:[.,]\d+)?)\s*(?:celsius|fok|c)\b.*fahrenheit", low)
        if m:
            return f"{num(m.group(1)):g} °C = {num(m.group(1)) * 9 / 5 + 32:g} °F."
        m = re.search(r"(\d+(?:[.,]\d+)?)\s*fahrenheit.*(?:celsius|fok)", low)
        if m:
            return f"{num(m.group(1)):g} °F = {(num(m.group(1)) - 32) * 5 / 9:.1f} °C."
        m = re.search(r"(\d+(?:[.,]\d+)?)\s*(?:liter|l)\b.*(?:deci|dl)", low)
        if m:
            return f"{num(m.group(1)):g} liter = {num(m.group(1)) * 10:g} deciliter."
        return None

    def _catalog(self, low, original):
        # mennyi rész
        if re.search(r"\b(hány része|hany resze|hány epizód|hany epizod|része van|resze van)\b", low):
            series = self.find(original, limit=1)
            if series:
                s = series[0]
                cur, total = self._episodes(s)
                if cur and total and total != cur:
                    return Answer(f"A(z) {self._title(s)} sorozatnak {cur} része érhető el (a tervezett {total}-ból).",
                                  "catalog", sources=[self._title(s)])
                if cur:
                    return Answer(f"A(z) {self._title(s)} sorozatnak {cur} része van.",
                                  "catalog", sources=[self._title(s)])

        # évad / státusz / pontszám
        series = self.find(original, limit=1)
        if series:
            s = series[0]
            title = self._title(s)
            if re.search(r"\b(milyen hosszú|mennyi ideig|hány perc)\b", low):
                pass
            if re.search(r"(pontszam|hany pontos|ertekeles|score|mennyi a pontja|hanyas)", low) and s.get("score"):
                return Answer(f"A(z) {title} értékelése {s['score']} a 10-es skálán.", "catalog", sources=[title])
            if re.search(r"(befejez|fut meg|fut-e|statusz|allapot)", low):
                state = {"FINISHED": "befejezett", "RELEASING": "jelenleg fut",
                         "NOT_YET_RELEASED": "még nem indult"}.get(s.get("status") or "", s.get("status") or "?")
                return Answer(f"A(z) {title} {state}.", "catalog", sources=[title])
            if re.search(r"(van magyar|magyar felirat|feliratos|magyarul nezheto)", low):
                has = s.get("hasHungarianSubtitles") or s.get("hasHungarianSub")
                return Answer(f"A(z) {title} " + ("magyar felirattal nézhető a CortexAnime-on." if has
                                                  else "egyelőre nem elérhető magyar felirattal."),
                              "catalog", sources=[title])
            if re.search(r"(mirol szol|tortenet|synopsis|tartalom|meselj rola)", low) and (s.get("synopsis") or "").strip():
                syn = s["synopsis"].strip()
                if len(syn) > 600:
                    syn = syn[:600].rsplit(" ", 1)[0] + "…"
                return Answer(f"{title}: {syn}", "catalog", sources=[title])
            if re.search(r"(mufaj|milyen tipus|kategoria|milyen kategori)", low) and s.get("genres"):
                return Answer(f"A(z) {title} műfaja: {', '.join(s['genres'])}.", "catalog", sources=[title])

        # ajánlás műfajra
        wanted = []
        for hu, en in GENRE_HU.items():
            if re.search(r"\b" + re.escape(hu) + r"\b", low):
                wanted.append(en)
        wanted = list(dict.fromkeys(wanted))
        if wanted and re.search(r"(ajanl|mutass|mit nezzek|javasolj|keresek|milyen .* van)", low):
            picks = self._by_genre(wanted, limit=3)
            if picks:
                names = ", ".join(self._title(p) for p in picks)
                return Answer(f"Ha a {', '.join(wanted).lower()} a kedvenced, ezeket érdemes megnézni: {names}.",
                              "catalog", sources=[self._title(p) for p in picks])

        # keresés címre — csak akkor, ha a kérdés tényleg egy címre mutat
        explicit = re.search(r"(keresd|keresem|hol van|hol talalom|van-e|van e|nezheto|"
                             r"nezzem meg|hol nezzem)", low)
        looks_like_lookup = explicit or (len(tokens(original)) <= 6 and self.is_title_query(original))
        if looks_like_lookup:
            hits = self.find(original, limit=3)
            if hits:
                s = hits[0]
                cur, total = self._episodes(s)
                extra = f" ({cur} rész)" if cur else ""
                return Answer(f"Ez megvan a kínálatban: {self._title(s)}{extra}, "
                              f"műfaj: {', '.join(s.get('genres') or ['?'])}.", "catalog",
                              sources=[self._title(s)])

        return None

    def is_title_query(self, query):
        """Igazi címkeresés: legalább két egyező token, köztük egy ritka (df kicsi)."""
        q = tokens(query)
        if len(q) < 2:
            return False
        for i, doc_tokens in enumerate(self.index.toks):
            doc_set = set(doc_tokens)
            hits = [t for t in q if t in doc_set]
            if len(hits) < 2:
                continue
            rare = [t for t in hits if self.index.df.get(t, 0) <= max(3, self.index.n // 30)]
            if rare:
                return True
        return False

    def _by_genre(self, wanted, limit=3):
        pool = [s for s in self.series if any(g in (s.get("genres") or []) for g in wanted)]
        pool.sort(key=lambda s: (-(s.get("score") or 0), self._title(s)))
        return pool[:limit]


def safe_eval(expr):
    """Csak számok és a négy alapművelet — nincs eval, nincs beépített név."""
    import ast
    allowed = (ast.Expression, ast.BinOp, ast.UnaryOp, ast.Constant, ast.Add, ast.Sub,
               ast.Mult, ast.Div, ast.Pow, ast.Mod, ast.USub, ast.UAdd, ast.FloorDiv)
    tree = ast.parse(expr, mode="eval")

    def walk(node):
        if not isinstance(node, allowed):
            raise ValueError("nem engedett kifejezés")
        if isinstance(node, ast.Constant):
            if not isinstance(node.value, (int, float)):
                raise ValueError("nem szám")
            return float(node.value)
        if isinstance(node, ast.BinOp):
            left, right = walk(node.left), walk(node.right)
            op = type(node.op)
            if op is ast.Add: return left + right
            if op is ast.Sub: return left - right
            if op is ast.Mult: return left * right
            if op is ast.Div:
                if right == 0: raise ZeroDivisionError("nullával osztás")
                return left / right
            if op is ast.FloorDiv:
                if right == 0: raise ZeroDivisionError("nullával osztás")
                return left // right
            if op is ast.Mod:
                if right == 0: raise ZeroDivisionError("nullával osztás")
                return left % right
            if op is ast.Pow:
                if abs(right) > 64: raise ValueError("túl nagy kitevő")
                return left ** right
        if isinstance(node, ast.UnaryOp):
            value = walk(node.operand)
            return -value if isinstance(node.op, ast.USub) else value
        raise ValueError("nem engedett")

    return walk(tree.body)
