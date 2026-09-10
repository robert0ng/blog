source "https://rubygems.org"

gem "jekyll-theme-basically-basic"

gem "github-pages"

group :jekyll_plugins do
  gem "jekyll-paginate"
  gem "jekyll-sitemap"
  gem "jekyll-feed"
  gem "jekyll-seo-tag"
end
gem "webrick", "~> 1.8"

# jekyll 3.9 (pulled in by github-pages) uses these without declaring them;
# Ruby 3.4+ removed them from the default gems, so bundle exec jekyll build
# fails on a modern Ruby without pinning them explicitly.
gem "csv"
gem "logger"
gem "base64"
gem "bigdecimal"

group :development do
  # Used by script/verify.sh to check the built site for broken internal
  # links/images (the class of bug fixed in the CNY post's image link).
  gem "html-proofer"
end
