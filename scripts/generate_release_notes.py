#!/usr/bin/env python3
"""
TourSplit Release Notes Generator
Extracts and formats detailed yet minimalistic "What's New" release notes
for GitHub Releases, in-app updates, and FCM push notifications.

Sources of truth (in order of preference):
1. Explicit notes passed via CLI argument or environment variable (if non-empty & non-default)
2. Version entry in CHANGELOG.md
3. _features list in lib/presentation/widgets/whats_new_dialog.dart
4. Recent git commits (conventional commits fallback)
"""

import os
import re
import sys
import argparse
import subprocess

ICON_EMOJI_MAP = {
    'account_circle': '👤',
    'person': '👤',
    'group': '👥',
    'people': '👥',
    'flash_on': '⚡',
    'bolt': '⚡',
    'layers': '🎨',
    'palette': '🎨',
    'brush': '🎨',
    'color_lens': '🎨',
    'pie_chart': '📊',
    'bar_chart': '📊',
    'analytics': '📊',
    'show_chart': '📈',
    'mark_email': '📬',
    'mail': '📬',
    'email': '📬',
    'send': '✈️',
    'system_update': '🚀',
    'cloud_download': '🚀',
    'rocket': '🚀',
    'upgrade': '🚀',
    'calculate': '🧮',
    'exposure': '🧮',
    'credit_card': '💳',
    'account_balance': '💳',
    'wallet': '💳',
    'payment': '💳',
    'receipt': '🧾',
    'security': '🛡️',
    'shield': '🛡️',
    'lock': '🔒',
    'notifications': '🔔',
    'sync': '🔄',
    'refresh': '🔄',
    'autorenew': '🔄',
    'check': '✅',
    'done': '✅',
    'verified': '✅',
    'timer': '⏱️',
    'speed': '⚡',
    'search': '🔍',
    'qr_code': '📱',
}

def get_emoji_for_icon(icon_name: str) -> str:
    cleaned = icon_name.lower().replace('_rounded', '').replace('_outlined', '').replace('_sharp', '')
    for key, emoji in ICON_EMOJI_MAP.items():
        if key in cleaned:
            return emoji
    return '✨'

def extract_features_from_whats_new_dialog(repo_root: str) -> list:
    dialog_path = os.path.join(repo_root, 'lib', 'presentation', 'widgets', 'whats_new_dialog.dart')
    if not os.path.exists(dialog_path):
        return []
    
    with open(dialog_path, 'r', encoding='utf-8') as f:
        content = f.read()

    features_match = re.search(r'_features\s*=\s*\[(.*?)\];', content, re.DOTALL)
    if not features_match:
        return []

    raw_block = features_match.group(1)
    pattern = re.compile(
        r'\(\s*icon:\s*Icons\.([a-zA-Z0-9_]+),\s*title:\s*[\'"](.*?)[\'"],\s*description:\s*[\'"](.*?)[\'"],?\s*\)',
        re.DOTALL
    )

    features = []
    for match in pattern.finditer(raw_block):
        icon_name, title, desc = match.groups()
        clean_title = ' '.join(title.split())
        clean_desc = ' '.join(desc.split())
        emoji = get_emoji_for_icon(icon_name)
        features.append({
            'icon': icon_name,
            'emoji': emoji,
            'title': clean_title,
            'description': clean_desc
        })
    return features

def extract_features_from_changelog(repo_root: str, version: str) -> list:
    changelog_path = os.path.join(repo_root, 'CHANGELOG.md')
    if not os.path.exists(changelog_path):
        return []
    
    clean_ver = version.lstrip('v')
    with open(changelog_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    in_target_version = False
    features = []
    header_regex = re.compile(rf'^#+\s*\[?v?{re.escape(clean_ver)}\]?')

    for line in lines:
        if header_regex.match(line.strip()):
            in_target_version = True
            continue
        elif in_target_version and (line.strip().startswith('##') or line.strip() == '---'):
            break
        elif in_target_version:
            stripped = line.strip()
            if not stripped:
                continue
            # Parse bullet: - <emoji> **<title>**: <desc>
            m = re.match(r'^[*-]\s*(?:([^\s*]+)\s+)?\*\*(.*?)\*\*:\s*(.*)', stripped)
            if m:
                emoji, title, desc = m.groups()
                features.append({
                    'emoji': emoji or '✨',
                    'title': title.strip(),
                    'description': desc.strip()
                })
            elif stripped.startswith(('- ', '* ')):
                bullet_text = stripped[2:].strip()
                features.append({
                    'emoji': '✨',
                    'title': bullet_text.split(':')[0].strip('* '),
                    'description': bullet_text
                })
    
    return features

def extract_from_git_commits(repo_root: str) -> list:
    try:
        res = subprocess.run(
            ['git', 'log', '-n', '15', '--pretty=format:%s'],
            cwd=repo_root, capture_output=True, text=True, check=True
        )
        commits = res.stdout.strip().splitlines()
        features = []
        for c in commits:
            c = c.strip()
            if not c or any(c.startswith(p) for p in ['Merge', 'chore(release)', 'chore: release', 'Bump', 'ci:']):
                continue
            # Parse conventional commit
            m = re.match(r'^(feat|fix|perf|refactor)(?:\((.*?)\))?:\s*(.*)', c, re.IGNORECASE)
            if m:
                kind, scope, desc = m.groups()
                emoji = '✨' if kind == 'feat' else '🐞' if kind == 'fix' else '⚡'
                title = scope.capitalize() if scope else kind.capitalize()
                features.append({
                    'emoji': emoji,
                    'title': title,
                    'description': desc
                })
        return features[:6]
    except Exception:
        return []

def is_default_or_generic(notes: str) -> bool:
    if not notes or not notes.strip():
        return True
    lower = notes.strip().lower()
    return (
        'split the costs, keep the memories' in lower and len(notes.strip().splitlines()) <= 2
        or lower == 'tour split release update!'
        or lower.startswith('toursplit update v')
        or lower.startswith('release update!')
    )

def build_release_notes(repo_root: str, version: str, explicit_notes: str = None) -> dict:
    clean_ver = version.lstrip('v')
    
    # 1. If explicit notes are provided and substantive, check them
    if explicit_notes and not is_default_or_generic(explicit_notes):
        body = explicit_notes.strip()
        lines = [l.strip() for l in body.splitlines() if l.strip()]
        first_line = lines[0] if lines else f'TourSplit v{clean_ver}'
        title = f'TourSplit v{clean_ver} - {first_line.replace("#", "").strip()}' if len(lines) > 1 else f'TourSplit v{clean_ver}'
        return {
            'title': title[:100],
            'body': body,
            'summary': f'TourSplit v{clean_ver} is now available with new features and improvements.'
        }
    
    # 2. Try CHANGELOG.md first, then WhatsNewDialog, then Git Commits
    features = extract_features_from_changelog(repo_root, clean_ver)
    if not features:
        features = extract_features_from_whats_new_dialog(repo_root)
    if not features:
        features = extract_from_git_commits(repo_root)
    
    if features:
        bullet_lines = []
        for feat in features:
            emoji = feat.get('emoji', '✨')
            title = feat.get('title', '').strip()
            desc = feat.get('description', '').strip()
            bullet_lines.append(f"- {emoji} **{title}**: {desc}")
        
        body = f"### What's New in TourSplit v{clean_ver} ✨\n\n" + "\n".join(bullet_lines)
        
        # Build attractive release title: e.g. TourSplit v1.4.1 - Feature 1, Feature 2 & Feature 3
        top_titles = [f['title'] for f in features[:3]]
        if len(top_titles) == 1:
            title_suffix = top_titles[0]
        elif len(top_titles) == 2:
            title_suffix = f"{top_titles[0]} & {top_titles[1]}"
        elif len(top_titles) >= 3:
            title_suffix = f"{top_titles[0]}, {top_titles[1]} & {top_titles[2]}"
        else:
            title_suffix = "Fresh Features & Polish"
            
        release_title = f"TourSplit v{clean_ver} - {title_suffix}"
        if len(release_title) > 95:
            release_title = f"TourSplit v{clean_ver} - {top_titles[0]} & {top_titles[1]}"
        if len(release_title) > 95:
            release_title = f"TourSplit v{clean_ver} - {top_titles[0]}"
            
        summary = f"v{clean_ver}: " + ", ".join(top_titles[:3]) + " and more."
        
        return {
            'title': release_title,
            'body': body,
            'summary': summary
        }
    
    # Fallback
    default_body = (
        f"### What's New in TourSplit v{clean_ver} ✨\n\n"
        f"- ⚡ **Performance & Stability**: Enhanced transaction reliability and smoother offline calculations.\n"
        f"- 🐞 **Bug Fixes**: Resolved minor interface glitches and improved dialog responsiveness.\n"
        f"- 🎨 **Visual Refinements**: Polished layouts and responsive feedback for trip settlements."
    )
    return {
        'title': f"TourSplit v{clean_ver} - Performance & Stability Update",
        'body': default_body,
        'summary': f"TourSplit v{clean_ver} is now available with stability and performance improvements."
    }

def main():
    parser = argparse.ArgumentParser(description="Generate detailed yet minimalistic What's New release notes")
    version_default = ""
    pubspec_path = os.path.join(args_root if 'args_root' in locals() else os.path.abspath(os.path.join(os.path.dirname(__file__), "..")), "pubspec.yaml")
    if os.path.exists(pubspec_path):
        with open(pubspec_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("version:"):
                    version_default = line.split(":")[1].strip().split("+")[0]
                    break
    if not version_default:
        version_default = "1.4.2"

    parser.add_argument("version", nargs="?", default=version_default, help="Release version (e.g. 1.4.2 or v1.4.2)")
    parser.add_argument("explicit_notes", nargs="?", default="", help="Optional explicit release notes")
    parser.add_argument("--repo-root", default=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    parser.add_argument("--github-output", action="store_true", help="Write step outputs to GITHUB_OUTPUT environment file")
    parser.add_argument("--body-only", action="store_true", help="Print only release body markdown")
    parser.add_argument("--title-only", action="store_true", help="Print only release title")
    parser.add_argument("--summary-only", action="store_true", help="Print only short summary")

    args = parser.parse_args()
    
    result = build_release_notes(args.repo_root, args.version, args.explicit_notes)
    
    if args.github_output:
        gh_out = os.environ.get("GITHUB_OUTPUT")
        if gh_out and os.path.exists(gh_out):
            with open(gh_out, "a", encoding="utf-8") as f:
                f.write(f"release_title={result['title']}\n")
                f.write(f"release_summary={result['summary']}\n")
                f.write("release_body<<EOF\n")
                f.write(result['body'] + "\n")
                f.write("EOF\n")
        else:
            print(f"Notice: GITHUB_OUTPUT not set. Outputting preview:\n")
            print(f"Title: {result['title']}")
            print(f"Summary: {result['summary']}")
            print(f"Body:\n{result['body']}")
        return

    if args.body_only:
        print(result['body'])
    elif args.title_only:
        print(result['title'])
    elif args.summary_only:
        print(result['summary'])
    else:
        print("=" * 60)
        print("TITLE:", result['title'])
        print("=" * 60)
        print("BODY:\n" + result['body'])
        print("=" * 60)
        print("SUMMARY:", result['summary'])
        print("=" * 60)

if __name__ == "__main__":
    main()
