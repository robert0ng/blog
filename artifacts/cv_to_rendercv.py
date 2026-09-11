#!/usr/bin/env python3
"""Convert _data/cv.json (this repo's single source of truth for CV
content) into a RenderCV-schema YAML file.

Run with the same Python that has rendercv + pyyaml installed -- see
generate-cv-pdf.sh, which invokes this via the rendercv pipx venv's
interpreter rather than the system python3.

Usage: cv_to_rendercv.py <path/to/cv.json> <path/to/output.yaml>
"""
import datetime
import json
import re
import sys

import yaml

SITE_URL = "https://www.robertnotes.com"

# Emoji/pictographs are decorative only in the source content and risk
# rendering as tofu boxes depending on the PDF viewer's font -- strip
# them rather than fight font configuration for a heart emoji.
_EMOJI_RE = re.compile(
    "["
    "\U0001F300-\U0001FAFF"
    "\U00002600-\U000027BF"
    "\U0001F1E6-\U0001F1FF"
    "\U0000FE00-\U0000FE0F"  # variation selectors (e.g. the VS16 after a heart glyph)
    "\U0000200D"  # zero-width joiner
    "]+",
    flags=re.UNICODE,
)


def strip_emoji(text):
    return _EMOJI_RE.sub("", text).strip()


# cv.json dates are free-text like "Feb, 2020", "Sep 1, 2004", "Current".
# RenderCV wants ISO dates (YYYY-MM or YYYY-MM-DD) or the literal
# "present". Parse what we can; fall back to passing the string through
# as a free-text `date` field (RenderCv accepts a plain `date:` instead
# of start/end when the value isn't a clean range) rather than guessing.
_MONTHS = {
    m.lower(): i
    for i, m in enumerate(
        [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ],
        start=1,
    )
}


def parse_date(value):
    if value is None:
        return None
    value = value.strip()
    if value.lower() in ("current", "present", ""):
        return "present"
    # "Feb, 2020" / "Sep, 2004"
    m = re.match(r"^([A-Za-z]{3,})\.?,?\s+(\d{4})$", value)
    if m:
        month = _MONTHS.get(m.group(1)[:3].lower())
        if month:
            return f"{m.group(2)}-{month:02d}"
    # "Sep 1, 2004"
    m = re.match(r"^([A-Za-z]{3,})\s+\d{1,2},\s+(\d{4})$", value)
    if m:
        month = _MONTHS.get(m.group(1)[:3].lower())
        if month:
            return f"{m.group(2)}-{month:02d}"
    # Bare year, e.g. "2016", "2010 " (awards has a trailing space)
    m = re.match(r"^(\d{4})$", value)
    if m:
        return value
    return None  # caller falls back to a free-text date field


def highlight_to_text(item):
    """A highlight is either a plain string, or {content, link,
    isSelfDomain} -- render the latter as a Markdown link, resolving
    isSelfDomain links against the site's own URL."""
    if isinstance(item, str):
        return item
    content = item.get("content", "")
    link = item.get("link")
    if not link:
        return content
    if item.get("isSelfDomain"):
        link = SITE_URL + link
    return f"[{content}]({link})"


def social_networks(profiles):
    out = []
    network_map = {"github": "GitHub", "stackoverflow": "StackOverflow"}
    for p in profiles or []:
        network = network_map.get((p.get("network") or "").lower())
        if network is None:
            continue  # unrecognized network name -- skip rather than guess
        username = p.get("username", "")
        if network == "StackOverflow":
            # RenderCV wants "user_id/username"; cv.json's profile URL is
            # ".../users/<id>/<username>" -- pull the id out of it.
            m = re.search(r"/users/(\d+)/", p.get("url", ""))
            if m:
                username = f"{m.group(1)}/{username}"
        out.append({"network": network, "username": username})
    return out


def experience_entries(work):
    entries = []
    for w in work or []:
        entry = {
            "company": w.get("company", ""),
            "position": w.get("position", ""),
        }
        start = parse_date(w.get("startDate"))
        end = parse_date(w.get("endDate"))
        if start:
            entry["start_date"] = start
            entry["end_date"] = end or "present"
        if w.get("summary"):
            entry["summary"] = w["summary"]
        highlights = [highlight_to_text(h) for h in w.get("highlights", [])]
        if highlights:
            entry["highlights"] = highlights
        entries.append(entry)
    return entries


def project_entries(projects):
    entries = []
    for p in projects or []:
        name = p.get("name", "")
        if p.get("website"):
            website = p["website"]
            if website.startswith("/"):
                website = SITE_URL + website
            name = f"[{name}]({website})"
        entry = {"name": name}
        date = parse_date(p.get("date"))
        if date:
            entry["date"] = date
        elif p.get("date"):
            entry["date"] = p["date"]
        if p.get("summary"):
            entry["summary"] = p["summary"]
        highlights = [highlight_to_text(h) for h in p.get("highlights", [])]
        if highlights:
            entry["highlights"] = highlights
        entries.append(entry)
    return entries


def education_entries(education):
    entries = []
    for e in education or []:
        entry = {
            "institution": e.get("institution", ""),
            "area": e.get("area", ""),
            "degree": e.get("studyType", ""),
        }
        start = parse_date(e.get("startDate"))
        end = parse_date(e.get("endDate"))
        if start:
            entry["start_date"] = start
            entry["end_date"] = end or "present"
        entries.append(entry)
    return entries


def award_entries(awards):
    # RenderCV's BulletEntry (a single `bullet` string) is the closest
    # generic fit for title + awarder + date + summary combined.
    entries = []
    for a in awards or []:
        parts = [f"**{a.get('title', '')}**"]
        if a.get("awarder"):
            parts.append(f"— {a['awarder']}")
        date = (a.get("date") or "").strip()
        if date:
            parts.append(f"({date})")
        bullet = " ".join(parts)
        if a.get("summary"):
            bullet += f": {a['summary']}"
        entries.append({"bullet": bullet})
    return entries


def publication_entries(publications):
    entries = []
    for p in publications or []:
        entry = {
            "title": p.get("name", ""),
            "authors": ["Robert Wang"],
        }
        if p.get("publisher"):
            entry["journal"] = p["publisher"]
        if p.get("website"):
            entry["url"] = p["website"]
        date = parse_date(p.get("releaseDate"))
        if date:
            entry["date"] = date
        elif p.get("releaseDate"):
            entry["date"] = p["releaseDate"]
        entries.append(entry)
    return entries


def keyword_entries(items, name_key):
    return [
        {
            "label": item.get(name_key, ""),
            "details": ", ".join(item.get("keywords", [])),
        }
        for item in items or []
    ]


def language_entries(languages):
    return [
        {"label": l.get("language", ""), "details": l.get("fluency", "")}
        for l in languages or []
    ]


def build_rendercv_data(cv):
    basics = cv.get("basics", {})
    location = basics.get("location", {})
    location_str = ", ".join(
        part for part in [location.get("city"), location.get("region")] if part
    )

    sections = {}
    if basics.get("summary"):
        sections["summary"] = [strip_emoji(basics["summary"])]
    if cv.get("work"):
        sections["experience"] = experience_entries(cv["work"])
    if cv.get("freelance-project"):
        sections["projects"] = project_entries(cv["freelance-project"])
    if cv.get("education"):
        sections["education"] = education_entries(cv["education"])
    if cv.get("awards"):
        sections["awards"] = award_entries(cv["awards"])
    if cv.get("publications"):
        sections["publications"] = publication_entries(cv["publications"])
    if cv.get("skills"):
        sections["skills"] = keyword_entries(cv["skills"], "name")
    if cv.get("languages"):
        sections["languages"] = language_entries(cv["languages"])
    if cv.get("interests"):
        sections["interests"] = keyword_entries(cv["interests"], "name")

    return {
        "cv": {
            "name": basics.get("name", ""),
            "headline": basics.get("label", ""),
            "location": location_str,
            "email": basics.get("email", ""),
            "website": basics.get("website", ""),
            "social_networks": social_networks(basics.get("profiles")),
            "sections": sections,
        },
        "design": {
            "theme": "classic",
            # Default degree_width (1cm) wraps "Master"/"Bachelor" onto
            # two lines ("Mas-ter"); widen it to fit on one.
            "entries": {"degree_width": "2.2cm"},
        },
        "locale": {"language": "english"},
        "settings": {
            "current_date": datetime.date.today().isoformat(),
            "bold_keywords": [],
            "pdf_title": f"{basics.get('name', 'CV')} - CV",
        },
    }


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <cv.json> <output.yaml>", file=sys.stderr)
        sys.exit(1)
    cv_json_path, output_path = sys.argv[1], sys.argv[2]

    with open(cv_json_path, encoding="utf-8") as f:
        cv = json.load(f)

    data = build_rendercv_data(cv)

    with open(output_path, "w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False, width=100)

    print(f"wrote {output_path}")


if __name__ == "__main__":
    main()
