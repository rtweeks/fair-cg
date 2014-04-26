require "yaml"

GEM_VERSIONS_URL = 'http://fair-cg.rubyforge.org/svn/gem-versions'

def latest_gem_version
  `svn ls #{GEM_VERSIONS_URL}`.collect do |ver|
    if ver =~ /(\d+).(\d+).(\d+)/
      [$1, $2, $3].collect! {|n| n.to_i}
    else
      [0,0,0]
    end
  end.max
end

desc "Fetch the latest version of the gem from RubyForge"
task :fetch_latest do
  ver = latest_gem_version
  rm_rf 'gem'
  sh("svn export #{GEM_VERSIONS_URL}/#{ver.join('.')} gem") &&
  File.open('gem/gem-version.yaml', 'w') do |vfile|
    YAML.dump(ver, vfile)
  end
end

desc "Build the latest tagged version of the gem"
task :gem => [:fetch_latest] do
  cd("gem") do
    sh("gem build fair-cg.gemspec")
  end
end
