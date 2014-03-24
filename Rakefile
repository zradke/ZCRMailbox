desc "Run ZCRMailbox unit tests"
task :test do
  $success = system("xctool -project Project/ZCRMailbox.xcodeproj -scheme 'ZCRMailbox' -destination 'platform=iOS Simulator,name=iPhone,OS=latest' -configuration Release clean test -freshSimulator -freshInstall")
  if $success
    puts "\033[0;32m** All tests succeeded!"
  else
    puts "\033[0;31m! Unit tests failed"
    exit(-1)
  end
end
task :default => :test

