JEKYLL = "bundle exec jekyll"

desc "Build the site"
task :build do
  sh "#{JEKYLL} build"
end

desc "Serve the site locally with auto-reload"
task :serve do
  sh "#{JEKYLL} serve --watch --livereload"
end

desc "Alias for serve"
task dev: :serve

desc "Remove the generated site and cache"
task :clean do
  sh "#{JEKYLL} clean"
  rm_rf Dir["_site_*"]
end

desc "Install Ruby dependencies"
task :install do
  sh "bundle install"
end

task default: :build
