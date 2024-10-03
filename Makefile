# Variables
VERSION_FILE = version.txt  # Or the file that manages the version
BRANCH = main               # Specify your default branch (main, master, etc.)
TAG_PREFIX = "v"            # Optional tag prefix
BUMP_PART = patch           # default bump2version part (patch, minor, major)

DEV_REQUIREMENTS = ./requirements/development.txt

# Default target to create a tag and a release
all: bump_version create_tag create_release

init:
	pip install --upgrade pip
	pip install -r $(DEV_REQUIREMENTS)

# Target to bump version using bump2version
bump_version:
	# Ensure the branch is up-to-date and on main
	git checkout $(BRANCH)
	git pull origin $(BRANCH)
	# Bump the version (patch by default)
	bump2version $(BUMP_PART)

# Target to create a Git tag
create_tag:
	# Get the new version from bump2version output
	VERSION=$$(bump2version --dry-run --list $(BUMP_PART) | grep new_version | cut -d= -f2)
	# Create a new tag on the main branch
	gh release create $(TAG_PREFIX)$$VERSION --title "Release $$VERSION" --notes "New release $$VERSION"

# Target to create a GitHub release
create_release:
	# Get the new version from the version.txt or similar file
	VERSION=$$(cat $(VERSION_FILE))
	# Push the tag and create a GitHub release
	git push origin $(TAG_PREFIX)$$VERSION
	gh release create $(TAG_PREFIX)$$VERSION --title "Release $$VERSION" --notes "New release $$VERSION"

# Utility to specify bump type (patch, minor, major)
bump:
	# Call make with the bump part (patch, minor, major)
	make BUMP_PART=$(BUMP_PART) all
