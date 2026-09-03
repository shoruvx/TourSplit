#!/bin/bash
set -e

# TourSplit One-Step Release Script
# Usage: ./scripts/release.sh <version> [release_notes]
# Example: ./scripts/release.sh 1.1.0 "Split payments and new logo"

if [ -z "$1" ]; then
  echo "Usage: ./scripts/release.sh <version> [release_notes]"
  echo "Example: ./scripts/release.sh 1.1.0 'Added new features'"
  exit 1
fi

VERSION=$1
NOTES=${2:-"TourSplit update v$VERSION: Split the costs, keep the memories."}
TAG="v$VERSION"

echo "=========================================="
echo "🚀 Preparing TourSplit Release $TAG"
echo "=========================================="

# 1. Update version in pubspec.yaml
echo "📝 Updating pubspec.yaml version to $VERSION..."
sed -i '' "s/^version: .*/version: $VERSION+$(date +%s)/" pubspec.yaml

# 2. Run tests to ensure quality
echo "🧪 Running automated tests..."
flutter test

# 3. Commit and tag
echo "📦 Committing version bump and tagging $TAG..."
git add pubspec.yaml
git commit -m "chore: release $TAG" || true
git tag -a "$TAG" -m "$NOTES"

# 4. Push tag to GitHub
echo "🌐 Pushing tag $TAG to GitHub..."
git push origin main || true
git push origin "$TAG"

echo "=========================================="
echo "🎉 Release $TAG initiated successfully!"
echo "GitHub Actions is now automatically building and publishing the APK release."
echo "Once published, all TourSplit users will receive the update prompt over-the-air!"
echo "=========================================="
