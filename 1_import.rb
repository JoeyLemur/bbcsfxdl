# Step 1 in the process: create the database file, get the CSV metadata, and import it.

require 'sqlite3'
require 'net/http'
require 'csv'

# Set up the database
db = SQLite3::Database.new "soundfiles.db"
db.execute 'create table if not exists soundfiles(id integer primary key, filename text, description text, seconds int, category text, cdnumber text, cdname text, tracknum int, size int, downloaded boolean default false, sha256 text)'
stmt = db.prepare 'insert into soundfiles(filename,description,seconds,category,cdnumber,cdname,tracknum) values (?,?,?,?,?,?,?)'

# Retrieve the metadata CSV file
csvdata = nil
Net::HTTP.start('bbcsfx.acropolis.org.uk',80) do |http|
  resp = http.get('/assets/BBCSoundEffects.csv')
  csvdata = resp.body
end

# Parse the data and insert into the database
CSV.parse(csvdata, :headers => true) do |row|
  stmt.execute(
  row['location'],
  row['description'],
  row['secs'].to_i,
  row['category'],
  row['CDNumber'],
  row['CDName'],
  row['tracknum'].to_i
  )
end

# Cleanup
stmt.close if stmt
sleep(1) # paranoia
db.close if db
