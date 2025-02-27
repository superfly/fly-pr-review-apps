#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
  echo -e "${YELLOW}Usage: $0 [major|minor|patch] [--push] [--update-latest]${NC}"
  echo -e "  major|minor|patch   - Which version component to bump"
  echo -e "  --push              - Push the new tag to remote (default: false)"
  echo -e "  --update-latest     - Also update the 'latest' tag (default: false)"
  echo
  echo -e "${YELLOW}Examples:${NC}"
  echo -e "  $0 patch            - Bump patch version locally"
  echo -e "  $0 minor --push     - Bump minor version and push to remote"
  echo -e "  $0 major --push --update-latest - Bump major version, push to remote, and update 'latest' tag"
  exit 1
}

# Parse arguments
BUMP_TYPE=""
PUSH=false
UPDATE_LATEST=false

for arg in "$@"; do
  case $arg in
    major|minor|patch)
      BUMP_TYPE=$arg
      ;;
    --push)
      PUSH=true
      ;;
    --update-latest)
      UPDATE_LATEST=true
      ;;
    *)
      echo -e "${RED}Error: Unknown argument '$arg'${NC}"
      usage
      ;;
  esac
done

# Validate arguments
if [ -z "$BUMP_TYPE" ]; then
  echo -e "${RED}Error: You must specify a version component to bump (major, minor, or patch)${NC}"
  usage
fi

# Get the latest semantic version tag
LATEST_TAG=$(git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)

if [ -z "$LATEST_TAG" ]; then
  echo -e "${RED}Error: No semantic version tags found. Create an initial tag like '0.1.0' first.${NC}"
  exit 1
fi

echo -e "${GREEN}Current version: $LATEST_TAG${NC}"

# Split the version into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST_TAG"

# Bump the specified component
case $BUMP_TYPE in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

# Create the new tag
NEW_TAG="${MAJOR}.${MINOR}.${PATCH}"
echo -e "${GREEN}Bumping $BUMP_TYPE version to: $NEW_TAG${NC}"

# Create the new tag locally
git tag $NEW_TAG
echo -e "${GREEN}Created tag $NEW_TAG${NC}"

# Update the 'latest' tag if requested
if [ "$UPDATE_LATEST" = true ]; then
  git tag -d latest 2>/dev/null || true
  git tag latest
  echo -e "${GREEN}Updated 'latest' tag to point to $NEW_TAG${NC}"
fi

# Push tags if requested
if [ "$PUSH" = true ]; then
  if [ "$UPDATE_LATEST" = true ]; then
    echo -e "${GREEN}Pushing new version tag $NEW_TAG...${NC}"
    git push origin $NEW_TAG

    echo -e "${GREEN}Force-pushing latest tag...${NC}"
    git push --force origin latest
  else
    echo -e "${GREEN}Pushing tag $NEW_TAG...${NC}"
    git push origin $NEW_TAG
  fi
  echo -e "${GREEN}Tags pushed successfully!${NC}"
else
  echo -e "${YELLOW}Tags created locally. Run the following to push:${NC}"
  if [ "$UPDATE_LATEST" = true ]; then
    echo -e "  git push origin $NEW_TAG"
    echo -e "  git push --force origin latest"
  else
    echo -e "  git push origin $NEW_TAG"
  fi
fi

echo -e "${GREEN}Version bump complete!${NC}"
