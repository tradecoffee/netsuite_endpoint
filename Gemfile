source 'https://www.rubygems.org'

#for bundle
ruby '2.6.6'

gemspec

gem 'endpoint_base', git: 'https://github.com/Follain/endpoint_base'

group :development do
  gem 'rake'
  gem 'pry'
  gem 'shotgun'
end

group :test do
  gem 'vcr'
  gem 'rack-test'
  gem 'webmock'
end

group :test, :development do
  gem 'pry-byebug'
end
