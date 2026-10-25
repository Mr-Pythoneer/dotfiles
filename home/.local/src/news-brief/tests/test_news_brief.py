"""Tests for feed parsing, story selection, Claude's answer and the page.

Run: python3 -m unittest discover -s tests   (from the repo directory)
"""
import importlib.machinery
import importlib.util
import json
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

# the script has no .py extension, so load it by path
_path = str(Path(__file__).resolve().parent.parent / "news-brief")
_loader = importlib.machinery.SourceFileLoader("news_brief", _path)
_spec = importlib.util.spec_from_loader("news_brief", _loader)
nb = importlib.util.module_from_spec(_spec)
_loader.exec_module(nb)

UTC = timezone.utc

RSS = b"""<?xml version="1.0"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:content="http://purl.org/rss/1.0/modules/content/">
<channel><title>Example</title>
<item><title>Parliament passes &amp;amp; budget</title><link>https://example.com/budget?utm_source=rss</link>
  <atom:link rel="self" href="https://example.com/feed"/>
  <pubDate>Sat, 10 Oct 2026 14:03:00 GMT</pubDate>
  <description><![CDATA[<p>The <b>budget</b> passed   after a long night.</p><script>x()</script>]]></description></item>
<item><title>Ask HN: something</title><link>https://news.ycombinator.com/item?id=1</link>
  <comments>https://news.ycombinator.com/item?id=1</comments>
  <pubDate>Sat, 10 Oct 2026 13:00:00 +0000</pubDate><description>Comments</description></item>
<item><title>Show HN: a thing</title><link>https://thing.dev/</link>
  <comments>https://news.ycombinator.com/item?id=2</comments><pubDate>Sat, 10 Oct 2026 12:00:00 +0000</pubDate></item>
<item><title>Sneaky</title><link>javascript:alert(1)</link></item>
<item><title></title><link>https://example.com/empty-title</link></item>
</channel></rss>"""

ATOM = b"""<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>Reg</title>
<entry><title type="html">Chip &lt;i&gt;shortage&lt;/i&gt; eases</title>
  <link rel="alternate" type="text/html" href="https://reg.example/chips"/>
  <updated>2026-10-10T09:30:00Z</updated><summary>Fabs are back.</summary></entry>
</feed>"""


def story(title, source, topic, hours_ago, now, url=None):
    return {"title": title, "url": url or f"https://{source.lower().replace(' ', '')}.example/{title.replace(' ', '-')}",
            "comments": "", "source": source, "topic": topic,
            "published": now - timedelta(hours=hours_ago) if hours_ago is not None else None, "summary": ""}


class FeedTests(unittest.TestCase):
    def test_rss(self):
        got = nb.parse_feed(RSS, "Example", "politics")
        self.assertEqual([s["title"] for s in got], ["Parliament passes & budget", "Ask HN: something", "Show HN: a thing"])
        first = got[0]
        self.assertEqual(first["summary"], "The budget passed after a long night.")
        self.assertEqual(first["published"], datetime(2026, 10, 10, 14, 3, tzinfo=UTC))
        self.assertEqual(first["url"], "https://example.com/budget?utm_source=rss")
        self.assertEqual(got[1]["summary"], "")       # HN's "Comments" blurb is dropped
        self.assertEqual(got[1]["comments"], "")      # same host as the link: nothing extra to show
        self.assertEqual(got[2]["comments"], "https://news.ycombinator.com/item?id=2")

    def test_atom(self):
        (s,) = nb.parse_feed(ATOM, "The Register", "tech")
        self.assertEqual(s["title"], "Chip shortage eases")
        self.assertEqual(s["url"], "https://reg.example/chips")
        self.assertEqual(s["published"], datetime(2026, 10, 10, 9, 30, tzinfo=UTC))
        self.assertEqual(s["summary"], "Fabs are back.")

    def test_clean_cuts_at_a_word(self):
        out = nb.clean("word " * 100, limit=22)
        self.assertTrue(out.endswith("…"))
        self.assertLessEqual(len(out), 23)
        self.assertNotIn("wor…", out)

    def test_bad_dates(self):
        self.assertIsNone(nb.parse_date("yesterday-ish"))
        self.assertIsNone(nb.parse_date(""))
        self.assertEqual(nb.parse_date("2026-10-10T09:30:00"), datetime(2026, 10, 10, 9, 30, tzinfo=UTC))


class SelectTests(unittest.TestCase):
    now = datetime(2026, 10, 10, 20, 28, tzinfo=UTC)

    def test_window_dedupe_and_caps(self):
        n = self.now
        stories = [story(f"Tech {i}", "Busy", "tech", i, n) for i in range(12)]
        stories += [story("Tech 1", "Other", "tech", 1, n)]                                     # same headline
        stories += [story("Copy", "Other", "tech", 3.5, n, url="https://busy.example/Tech-3/?utm_medium=x")]  # same link
        stories += [story("Old news", "Quiet", "politics", 30, n), story("Older", "Quiet", "politics", 31, n),
                    story("Oldest", "Quiet", "politics", 33, n), story("Ancient", "Quiet", "politics", 50, n)]
        got = nb.select(stories, n - timedelta(hours=10), per_feed=5, per_topic=30, oldest=n - timedelta(hours=36))
        self.assertEqual([s["title"] for s in got["tech"]], [f"Tech {i}" for i in range(5)])
        # a quiet outlet still shows its 2 newest from the last 36 hours
        self.assertEqual([s["title"] for s in got["politics"]], ["Old news", "Older"])

    def test_per_topic_cap_newest_first(self):
        n = self.now
        stories = [story(f"S{i}", f"Outlet {i}", "tech", i * 0.1, n) for i in range(10)]
        got = nb.select(stories, n - timedelta(hours=10), per_feed=8, per_topic=4)
        self.assertEqual([s["title"] for s in got["tech"]], ["S0", "S1", "S2", "S3"])
        self.assertEqual(got["politics"], [])


class SummaryTests(unittest.TestCase):
    def test_structured_output(self):
        out = json.dumps({"type": "result", "result": "", "structured_output": {"tldr": "x", "tech": [], "politics": []}})
        self.assertEqual(nb.parse_claude(out)["tldr"], "x")

    def test_json_in_text(self):
        out = json.dumps({"result": 'Here:\n```json\n{"tldr": "y", "tech": [], "politics": []}\n```'})
        self.assertEqual(nb.parse_claude(out)["tldr"], "y")

    def test_errors(self):
        self.assertIsNone(nb.parse_claude("not json"))
        self.assertIsNone(nb.parse_claude(json.dumps({"is_error": True, "result": "{}"})))
        self.assertIsNone(nb.parse_claude(json.dumps({"result": "no json here"})))

    def test_tidy_drops_unknown_sources(self):
        raw = {"tldr": " hi ", "tech": [{"title": "A", "text": "t", "sources": [1, 99, 1, "2"]}, {"text": ""}, "junk"],
               "politics": None}
        got = nb.tidy_summary(raw, {1, 2})
        self.assertEqual(got, {"tldr": "hi", "tech": [{"title": "A", "text": "t", "sources": [1]}], "politics": []})


class PageTests(unittest.TestCase):
    now = datetime(2026, 10, 10, 20, 30).astimezone()

    def picked(self):
        a = story("<img src=x onerror=alert(1)>", "Tech Site", "tech", 1, self.now)
        b = story("Second", "Tech Site", "tech", 2, self.now)
        c = story("Vote", "Paper", "politics", 3, self.now)
        for i, s in enumerate((a, b, c), 1):
            s["id"] = i
        return {"tech": [a, b], "politics": [c]}

    def test_escapes_and_links(self):
        summary = {"tldr": "<script>bad()</script>", "tech": [{"title": "T", "text": "x", "sources": [1, 2]}],
                   "politics": [{"title": "", "text": "y", "sources": [3]}]}
        page = nb.render(self.picked(), summary, "", self.now, prev="older.html")
        self.assertNotIn("<script>bad", page)
        self.assertNotIn("<img src=x", page)
        self.assertIn("&lt;script&gt;bad()", page)
        self.assertIn(">Tech Site</a>", page)
        self.assertIn(">Tech Site 2</a>", page)   # second story from the same outlet
        self.assertEqual(page.count('class="cited"'), 3)
        self.assertIn('href="older.html"', page)
        self.assertIn("Evening news", page)

    def test_without_summary(self):
        page = nb.render(self.picked(), None, "Claude took too long", self.now, failed=["NPR: timed out"])
        self.assertIn("No summary this time: Claude took too long", page)
        self.assertIn("Couldn&#x27;t reach: NPR", page)

    def test_teaser(self):
        p = self.picked()
        self.assertEqual(nb.teaser(None, p), p["tech"][0]["title"] + " · Vote")
        self.assertTrue(nb.teaser({"tldr": "word " * 60}, p).endswith("…"))


class DeliveryTests(unittest.TestCase):
    def test_waits_for_the_half_hour(self):
        t = datetime(2026, 10, 10, 7, 28, 40)
        self.assertEqual(nb.delivery_time(t), datetime(2026, 10, 10, 7, 30))
        t = datetime(2026, 10, 10, 20, 26, 5)
        self.assertEqual(nb.delivery_time(t), datetime(2026, 10, 10, 20, 30))

    def test_late_runs_go_now(self):
        for t in (datetime(2026, 10, 10, 7, 30, 0), datetime(2026, 10, 10, 9, 12), datetime(2026, 10, 10, 7, 24)):
            self.assertEqual(nb.delivery_time(t), t)

    def test_edition_names(self):
        self.assertEqual(nb.edition_name(datetime(2026, 1, 1, 7, 30)), "Morning")
        self.assertEqual(nb.edition_name(datetime(2026, 1, 1, 14, 0)), "Afternoon")
        self.assertEqual(nb.edition_name(datetime(2026, 1, 1, 20, 30)), "Evening")


if __name__ == "__main__":
    unittest.main()
