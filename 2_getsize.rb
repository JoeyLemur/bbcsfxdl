# Step 2 in the process: scrape the site for the file sizes for each file and store it.

require 'sqlite3'
require 'net/http'

# Open the database
db = SQLite3::Database.open('soundfiles.db')

# Get a list of entries that don't have a file size stored
rs = db.execute('select id,filename from soundfiles where size is null')
rowcount = rs.size
STDERR.puts "#{Time.now.to_s} : #{rowcount} rows to process"

# Prepare the update statement
stmt = db.prepare('update soundfiles set size=? where id=?')

# Open the http connectionj
http = Net::HTTP.start('bbcsfx.acropolis.org.uk',80)

# Count of how many rows we've processed
count = 0

# Iterate the rows
rs.each do |row|
  # Increment the row count and report
  count += 1
  STDERR.puts "#{Time.now.to_s} : #{count} of #{rowcount}" if count % 10 == 0
  # Get the HEAD of the file
  resp = http.head("/assets/#{row[1]}")
  # Update the row in the database
  stmt.execute(resp.content_length.to_i, row[0].to_i)
end

# Cleanup
stmt.close if stmt
sleep(1) # paranoia
db.close if db
