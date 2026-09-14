# TourSplit Assistant Guidelines

## Release Management & "What's New" Standard
Whenever preparing, bumping, or publishing a new release:
1. **Always write detailed yet minimalistic features** in What's New on GitHub releases every time.
2. Maintain `lib/presentation/widgets/whats_new_dialog.dart` `_features` and `CHANGELOG.md` with:
   `- <Emoji> **<Feature Title>**: <1-2 Sentence Crisp Description>`
3. The release pipeline in `.github/workflows/release.yml` and `scripts/release.sh` uses `scripts/generate_release_notes.py` to ensure all GitHub releases, tags, and FCM notifications contain these detailed features automatically.
