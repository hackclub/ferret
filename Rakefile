# frozen_string_literal: true

desc "Ingest CSV into SQLite"
task :ingest do
  ruby "bin/ingest"
end

desc "Embed unvectorized rows"
task :vectorize do
  ruby "bin/vectorize"
end

desc "Start the web server"
task :server do
  ruby "app.rb"
end
