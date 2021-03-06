begin
  require 'bundler/setup'
  require 'albacore'
  require 'configatron'  
  require 'fileutils'
  require File.dirname(__FILE__) + "/Tools/Rake/quicktemplate.rb"

rescue LoadError
  puts 'Bundler and all the gems need to be installed prior to running this rake script. Installing...'
  system("gem install bundler --source http://rubygems.org")
  sh 'bundle install'
  system("bundle exec rake", *ARGV)
  exit 0
end

task :rebuild => [ :clean, :configure, :restore, :build, :templates ]

task :default => [ :rebuild, :tests, :specs ]

desc "Prepares necessary configuration for build"
task :configure do
  project = "Machine.Specifications"
  target = ENV['target'] || 'Debug'

  build_config = {
    :target => target,
    :sign_assembly => ENV.include?('SIGN_ASSEMBLY'),
    :out_dir => "Build/#{target}/",
    :nunit_framework => "net-3.5",
    :mspec_options => (["--teamcity"] if ENV.include?('TEAMCITY_PROJECT_NAME')) || []
  }

  configatron.nuget.key = Configatron::Dynamic.new do
    next File.read('NUGET_KEY') if File.readable?('NUGET_KEY')
  end
  configatron.project = Configatron::Delayed.new do
    "#{project}#{'-Signed' if configatron.sign_assembly}"
  end
  configatron.distribution.dir = Configatron::Delayed.new do
    "Distribution/"
  end
  configatron.version.full = Configatron::Delayed.new do
    open("|Tools/GitFlowVersion/GitFlowVersion.exe").read().scan(/NugetVersion":"(.*)"/)[0][0][0,20]
  end
  configatron.version.short = Configatron::Delayed.new do
    open("|Tools/GitFlowVersion/GitFlowVersion.exe").read().scan(/ShortVersion":"(.*)"/)[0][0]
  end  

  configatron.configure_from_hash build_config
  #configatron.protect_all!
  puts configatron.inspect
end

desc "Prepares the working directory for a new build"
task :clean do
  filesToClean = FileList.new
  filesToClean.include('teamcity-info.xml')
  filesToClean.include('Source/**/obj')
  filesToClean.include('Build')
  filesToClean.include('Distribution')
  filesToClean.include('Specs')
  filesToClean.include('**/*.template')
  # Clean template results.
  filesToClean.map! do |f|
  next f.ext if f.pathmap('%x') == '.template'
  f
  end
  FileUtils.rm_rf filesToClean
  
  Dir.mkdir 'Distribution'
  Dir.mkdir 'Specs'
end

task :restore do
  nopts = %W(
   Tools/Nuget/NuGet.exe restore ./Machine.Specifications.sln
  )

  sh(*nopts)
end

desc "Run a simple clean/build"
msbuild :build do |msb|
  msb.solution = "./Machine.Specifications.sln"
  msb.targets = [:Clean, :Build]
  msb.use :net4
  msb.verbosity = :minimal
  msb.properties = {
     :Configuration => configatron.target,
     :TrackFileAccess => false,
     :SolutionDir => File.expand_path('.'),
     :SignAssembly => configatron.sign_assembly,
     :Platform => 'Any CPU'
  }
end

task :specs  => [:rebuild] do
  puts 'Running Specs...'

  specs = FileList.new("#{configatron.out_dir}/Tests/*.Specs.dll").exclude(/Clr4/)
  sh "#{configatron.out_dir}/mspec.exe", "--html", "Specs/#{configatron.project}.Specs.html", *(configatron.mspec_options + specs)

  specs = FileList.new("#{configatron.out_dir}/Tests/*.Clr4.Specs.dll")
  sh "#{configatron.out_dir}/mspec-clr4.exe", *(configatron.mspec_options + specs)

  puts "Wrote specs to Specs/#{configatron.project}.Specs.html"
end

desc "Run all nunit tests"
nunit :tests => [:rebuild] do |cmd|
  cmd.command = "Source/packages/NUnit.Runners/tools/nunit-console-x86.exe"
  cmd.assemblies = FileList.new("#{configatron.out_dir}/Tests/*.Tests.dll").to_a
  #cmd.results_path = "Specs/test-report.xml"
  #cmd.no_logo
  cmd.parameters = [
    "/framework=#{configatron.nunit_framework}",
	"/nothread",
	"/work=Specs"
  ]
end

task :templates do
  #Write teamcity build number
  puts "##teamcity[buildNumber '#{configatron.version.short}']"
  
  #Prepare templates
  FileList.new('**/*.template').each do |template|
    QuickTemplate.new(template).exec(configatron)
  end
end

desc "Package build artifacts as a NuGet package and a symbols package"
task :createpackage => [ :default ] do
	opts = %W(
	  Tools/Ripple/Ripple.exe create-packages --version #{configatron.version.full} --symbols --verbose --destination #{configatron.distribution.dir}
	  )

  sh(*opts) do |ok, status|
	ok or fail "Command failed with status (#{status.exitstatus})"
  end
end

desc "Publishes the NuGet package"
task :publishpackage => [ :default ] do
  raise "NuGet access key is missing, cannot publish" if configatron.nuget.key.nil?

  opts = %W(
	Tools/Ripple/Ripple.exe publish #{configatron.version.full} #{configatron.nuget.key} --symbols --artifacts #{configatron.distribution.dir} --verbose         
  )

  sh(*opts) do |ok, status|
	ok or fail "Command failed with status (#{status.exitstatus})"
  end
end