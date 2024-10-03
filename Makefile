# Variables
VERSION_FILE = version.txt  # Or the file that manages the version
BRANCH = main               # Specify your default branch (main, master, etc.)
TAG_PREFIX = "v"            # Optional tag prefix
BUMP_PART = patch           # default bump2version part (patch, minor, major)

DEV_REQUIREMENTS = ./requirements/development.txt

# Get the version from the version file
VERSION := $(shell cat $(VERSION_FILE))
# Full tag name: Prefix + Version
FULL_TAG = $(TAG_PREFIX)$(VERSION)

# Default target to create a tag and a release
all: bump_version create_tag_release

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
	# Now update the VERSION variable
	VERSION=$$(cat $(VERSION_FILE))

# Target to create a Git tag
create_tag_release:
	# Create a new tag on the main branch and push it
	git tag $(FULL_TAG)
    git push origin $(FULL_TAG)

	# Create a new GitHub release with the pushed tag
	gh release create $(FULL_TAG) --title "Release $(FULL_TAG)" --notes "New release $(FULL_TAG)"

# Utility to specify bump type (patch, minor, major)
bump:
	# Call make with the bump part (patch, minor, major)
	make BUMP_PART=$(BUMP_PART) all
