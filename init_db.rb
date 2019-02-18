require "sqlite3"

# Open a database
db_directory = "db"
Dir.mkdir(db_directory) unless File.exists?(db_directory)
db = SQLite3::Database.new "#{db_directory}/database.db"

# Create tables
db.execute <<-SQL
  CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    username VARCHAR(255),
    password VARCHAR(512),
    /* celestial, admin default celestial */
    role VARCHAR(255) DEFAULT "celestial",
    /* 1 male, 2 female */
    sex VARCHAR DEFAULT "male",
    /* 2 Dating status, 1 Quit game, 0 Init status, -1 Passive state*/
    state INTEGER DEFAULT 0
  );
 SQL

db.execute <<-SQL
  CREATE TABLE boxes (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255)
  );
SQL

db.execute <<-SQL
  CREATE TABLE cards (
    id INTEGER PRIMARY KEY,
    owner_id INTEGER,
    gainer_id INTEGER DEFAULT 0,
    box_id INTEGER DEFAULT 0
  );
SQL

db.execute <<-SQL
  CREATE TABLE notifications (
    id INTEGER PRIMARY KEY,
    recipient_id INTEGER,
    body VARCHAR(1024),
    /* 1 Have read, 0 unread */
    read INTEGER DEFAULT 0,
    timestamp TEXT
  );
SQL

# Execute a few inserts
["male", "female"].each do |pair|
  db.execute("INSERT INTO boxes (name) VALUES (?)", pair)
end

db.execute("INSERT INTO users (username, password, role) VALUES (?, ?, ?)", ["admin", "admin", "admin"])
db.execute("INSERT INTO cards (owner_id) VALUES (?)", 1)
