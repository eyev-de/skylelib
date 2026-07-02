# skylelib_prebuilt.rb — resolve (and if needed download) the prebuilt
# skylelib.xcframework that the ios/ and macos/ flutter_eap podspecs link.
#
# Resolution order (first hit wins):
#   1. ENV['SKYLELIB_DIST']            — explicit override (unzipped release)
#   2. <skylelib repo>/dist            — source-tree development (build_sdk.sh)
#   3. <plugin>/.skylelib/<version>    — per-version cache, downloaded from the
#      public GitHub release matching the plugin's pubspec version. This is the
#      path taken when the plugin is consumed as a pub git dependency.
#
# Returns the dist dir that contains skylelib.xcframework, or raises.

def skylelib_pubspec_version(plugin_dir)
  v = File.read(File.join(plugin_dir, 'pubspec.yaml'))[/^version:\s*([0-9]+\.[0-9]+\.[0-9]+)/, 1]
  raise 'flutter_eap: could not parse version: from pubspec.yaml' unless v
  v
end

def skylelib_resolve_dist(podspec_dir)
  plugin  = File.expand_path('..', podspec_dir)
  version = skylelib_pubspec_version(plugin)

  override = ENV['SKYLELIB_DIST']
  return override if override && !override.empty?

  repo_dist = File.expand_path(File.join(plugin, '..', '..', '..', 'dist'))
  return repo_dist if File.directory?(File.join(repo_dist, 'skylelib.xcframework'))

  cache = File.join(plugin, '.skylelib', version)
  return cache if File.directory?(File.join(cache, 'skylelib.xcframework'))

  asset = "skylelib-#{version}-xcframework.zip"
  url   = "https://github.com/eyev-de/skylelib/releases/download/v#{version}/#{asset}"
  zip   = File.join(cache, asset)
  require 'fileutils'
  FileUtils.mkdir_p(cache)
  puts "flutter_eap: downloading #{url}"
  system('curl', '-fsSL', '--retry', '3', '-o', zip, url) or
    raise "flutter_eap: download failed: #{url}\n" \
          'Download/unzip the release yourself and set SKYLELIB_DIST to it instead.'
  system('unzip', '-q', '-o', zip, '-d', cache) or raise "flutter_eap: could not unzip #{zip}"
  FileUtils.rm_f(zip)
  unless File.directory?(File.join(cache, 'skylelib.xcframework'))
    raise "flutter_eap: #{asset} did not contain skylelib.xcframework"
  end
  cache
end
