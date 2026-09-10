#!/bin/sh
# Verify the site builds and has no broken internal links/images.
# Run this after any content change, before committing.
#
# Requires Ruby matching .ruby-version (see that file for why: github-pages
# pins an old jekyll/liquid that breaks on newer Rubies). If you don't have
# a matching Ruby active, install it with a version manager first, e.g.:
#   brew install rbenv && rbenv install "$(cat .ruby-version)"
set -e
cd "$(dirname "$0")/.."

want_ruby="$(cat .ruby-version)"
have_ruby="$(ruby -e 'print RUBY_VERSION')"
if [ "$have_ruby" != "$want_ruby" ]; then
  echo "warning: active Ruby is $have_ruby, .ruby-version wants $want_ruby" >&2
  echo "         the build may fail on a Ruby this project isn't pinned to." >&2
fi

echo "==> bundle install"
bundle check >/dev/null 2>&1 || bundle install

echo "==> jekyll build"
bundle exec jekyll build --strict_front_matter

echo "==> checking built site for broken internal links/images"
bundle exec htmlproofer ./_site \
  --disable-external \
  --allow-hash-href

echo "==> OK"
