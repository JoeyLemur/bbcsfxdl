# Step 3 in the process:  Actually do the downloads.
# Update the DOWNLOAD_LIMIT constant to limit how much to do per run.

require 'sqlite3'
require 'net/http'
require 'digest'

# Where to store the downloaded stuff
DLDIR = '/path/to/downloads'

# Define convenience values
KBYTE = 1024
MBYTE = KBYTE * 1024
GBYTE = MBYTE * 1024

# Configure how much to download at one go
DOWNLOAD_LIMIT = 20 * GBYTE

# Pretty-print decimal numbers
# https://dzone.com/articles/format-number-thousands
def commas(number)
  return sprintf("%d", number).gsub(/(\d)(?=\d{3}+$)/, '\1,')
end

# Count how many bytes have been downloaded
downloaded = 0

# Make sure the download directory exists
Dir.mkdir(DLDIR) if not Dir.exist?(DLDIR)

# Open the database
db = SQLite3::Database.open('soundfiles.db')

# Prepare the update statement
stmt = db.prepare("update soundfiles set downloaded=?, sha256=? where id=?")

# Get the list of things-to-download
rs = db.execute("select id,filename,size from soundfiles where downloaded = 0")
rowcount = rs.size
STDERR.puts "#{Time.now} : #{rowcount} to download"
if rowcount == 0 then
  STDERR.puts "Ending run, nothing to do."
  Kernel.exit(0)
end

# Open up the http connection
http = Net::HTTP.start('bbcsfx.acropolis.org.uk',80)

# Init count of how many rows we've worked with
count = 0

# Iterate over the rows
rs.each do |row|
  # Stop if we're over the defined download-per-go byte limit
  break if downloaded >= DOWNLOAD_LIMIT
  # Increment row count and spit out information
  count += 1
  STDERR.puts "#{Time.now}: #{commas(count)}/#{commas(rowcount)} - #{commas(DOWNLOAD_LIMIT - downloaded)} bytes left - #{commas(row[0])} : #{row[1]} : #{commas(row[2])}"

  # Determine the path where to write the file
  filename = "#{DLDIR}/#{row[1]}"

  # Download the data
  resp = http.get("/assets/#{row[1]}")

  # Write the data out
  open(filename,'wb') { |file| file.write(resp.body) }
  
  # Get the filesize of the data we wrote
  filesize = File.size(filename).to_i

  # Paranoia check -- file size should match what we expect
  if filesize != row[2].to_i then
    STDERR.puts <<-EOS
    ***ARGH ARGH ARGH***
    Filesizes not the same!
    Expected #{row[2].to_i}, got #{filesize.to_i}
    EOS
    stmt.close if stmt
    db.close if db
    Kernel.exit(1)
  end

  # Hash the file
  hashdigest = Digest::SHA256.file(filename).hexdigest

  # Update database
  stmt.execute(1,hashdigest,row[0].to_i)

  # Add to the downloaded bytes counter
  downloaded += filesize
end

# End and cleanup
STDERR.puts "#{Time.now}: Ending run with #{commas(downloaded)} bytes downloaded, #{commas(count)} of #{commas(rowcount)} files downloaded."

stmt.close if stmt
sleep(1)  # More paranoia
db.close if stmt

