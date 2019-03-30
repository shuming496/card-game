require 'sqlite3'

# Open a database
db_directory = 'db'
db_path = db_directory + '/database.db'

Dir.mkdir(db_directory) unless File.exist?(db_directory)

if File.exist?(db_path)
  puts 'The database already exists.'
  return
end

db = SQLite3::Database.new(db_path)
  

# Create tables
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    username VARCHAR(255),
    username2 VARCHAR(255),
    password VARCHAR(512),
    /* celestial, admin default celestial */
    role VARCHAR(255) DEFAULT "celestial",
    /* 1 male, 2 female */
    sex VARCHAR DEFAULT "male",
    /* 2 Dating status, 1 Quit game, 0 Init status, -1 Passive state*/
    state INTEGER DEFAULT 0,
    game_times INTEGER DEFAULT 0,
    language VARCHAR(64)
  );
SQL

db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS boxes (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255)
  );
SQL

db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS cards (
    id INTEGER PRIMARY KEY,
    owner_id INTEGER,
    gainer_id INTEGER DEFAULT 0,
    box_id INTEGER DEFAULT 0
  );
SQL

db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS notifications (
    id INTEGER PRIMARY KEY,
    recipient_id INTEGER,
    body VARCHAR(1024),
    /* 1 Have read, 0 unread */
    read INTEGER DEFAULT 0,
    timestamp TEXT
  );
SQL

# Execute a few inserts
%w[male female].each do |pair|
  db.execute('INSERT INTO boxes (name) VALUES (?)', pair)
end

db.execute('INSERT INTO users (username, username2, password, role) VALUES (?, ?, ?, ?)', %w[admin admin admin admin])
db.execute('INSERT INTO cards (owner_id) VALUES (?)', 1)
