source "http://rubygems.org"

gem 'chef',          "~> 12.4"
gem 'formatador',    "~> 0.2"
gem 'gorillib',      "~> 0.1"
gem 'simplecov',     ">= 0.5", :require => false, :group => :test
gem 'simplecov-rcov'
gem 'coveralls', :require => false
gem 'rspec',       ">= 2.5"

group :development do
  gem 'bundler',     "~> 1"
  gem 'jeweler',     "~> 1.6"
  gem 'yard',        "~> 0.6"
  gem 'redcarpet',   "~> 2"
end

group :test do
  gem 'spork',       ">= 0.9.0", :platform => :mri
  gem 'rcov',        ">= 0.9.9", :platform => :ruby_18
  gem 'ruby_gntp'
  gem 'guard',         "~> 1"
  gem 'guard-rspec'
  gem 'guard-yard'
end

group :support do
  gem 'pry'
  gem 'grit'
end
