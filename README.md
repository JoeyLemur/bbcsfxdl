# bbcsfxdl
Scripts to download the BBC Sound Effects archive

## Description
Three Ruby scripts I hacked together in a couple hours to download the BBC Sound Effects archive (http://bbcsfx.acropolis.org.uk/) in a managable manner.

## Usage
- This was developed on Ruby 2.5, and requires the sqlite3 gem.
- Two items need your attention in 3_downloads.rb -- path to store downloaded files (DLDIR), and the amount of data to download per run.

- Run 1_import.rb first to set up the database.
- Run 2_getsize.rb second to download the file size of each file and store in the database.
- Run 3_download.rb third (and repeatedly) to download the actual files and update the database with the file's SHA256 hash, as well as mark it as downloaded.

- Just about everything assumes you're running from the command line, and from the directory that the scripts are in.

## Support
Bwahahahaha. This is not a production ready tool. It works well enough for me, and I like to think the source code is readable enough for anyone with passing familiarity with Ruby. I wrote it while drinking beer, there's probably better ways of writing it, I take no responsibility for it, use it at your own risk.

