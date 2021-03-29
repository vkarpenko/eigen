source 'https://rubygems.org'

gem 'cocoapods', "~> 0.39"
gem 'cocoapods-keys'

# 1.6.7 contains the OS X build fix.
gem 'nokogiri', '1.11.0.rc1'

group :development do
  gem 'lowdown'
  # Depends on older xcodeproj gem that is incompatible with current CocoaPods.
  #gem 'synx', :git => "https://github.com/orta/synx", :branch => "spaces_to-underscores"
end

group :test do
  gem 'fui'
  gem 'xcpretty'
  gem 'second_curtain'
  gem 'danger'
end

group :distribution do
  gem 'deliver'
  gem 'match'
  gem 'pilot'
  gem 'gym'
  gem 'fastlane'
end
