# coding: utf-8
# server.rb
require "sinatra"
require "sinatra/json"
require "erb"
require "rufus-scheduler"
require "sqlite3"
require "date"

class App < Sinatra::Base

  # Pull execute lock
  @@pull_executing = false
  
  # New database object
  db = SQLite3::Database.new "db/database.db"

  scheduler = Rufus::Scheduler.new

  ENV["TZ"] = "Asia/Shanghai"
  scheduler.cron "0 0 * * *" do
    p "hello"
    db.execute("UPDATE users SET state=? WHERE state=? OR state=?", 0, 1, 2)
    db.execute("UPDATE cards SET gainer_id=?, box_id=? WHERE gainer_id != ?", 0, 0, 0)
    db.execute("DELETE FROM notifications")
  end
  
  enable :sessions

  get "/" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("/signin")
    else
      @user_username = db.execute("SELECT username FROM users WHERE id=?", @user_id)[0][0]
      @user_sex = db.execute("SELECT sex FROM users WHERE id=?", @user_id)[0][0]
      @user_state = db.execute("SELECT state FROM users WHERE id=?", @user_id)[0][0]
      @card_owner_id = db.execute("SELECT owner_id FROM cards WHERE gainer_id=?", @user_id)
      unless @card_owner_id.empty? then
        @card_owner_username = db.execute("SELECT username FROM users WHERE id=?", @card_owner_id)[0][0]        
      end
      @card_box_id = db.execute("SELECT box_id FROM cards WHERE owner_id=?", @user_id)[0][0]
      #      @card_gainer_id = db.execute("SELECT gainer_id FROM cards WHERE owner_id=?", @user_id)
      @card_male_count = db.execute("SELECT COUNT(id) FROM cards WHERE box_id=(SELECT id FROM boxes WHERE name=?) and  gainer_id=?", "male", 0)[0][0]
      @card_female_count = db.execute("SELECT COUNT(id) FROM cards WHERE box_id=(SELECT id FROM boxes WHERE name=?) and  gainer_id=?", "female", 0)[0][0]
      @notifications_noread = db.execute("SELECT id FROM notifications WHERE recipient_id=? AND read=?", @user_id, 0)
      erb :index
    end
  end

  get "/signin" do
    @user_id = session[:user_id]
    unless @user_id.nil? then
      redirect to("/")
    end

    @no_login = true
    erb :signin
  end

  post "/signin" do
    @user_id = session[:user_id]
    unless @user_id.nil? then
      redirect to("/")
    end
    
    username = params["username"]
    password = params["password"]

    user_id = db.execute("SELECT id FROM users WHERE username=? AND password=?", username, password)
    if user_id.empty? then
      @flash_message = "用户名或密码错误！"
      erb :signin
    else
      session[:user_id] = user_id
      session[:executing] = false
      redirect to("/")
    end
  end

  get "/card/push" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      json :status => "error"
    else
      loop do
        if session[:executing] == false then
          break
        end
        next
      end
      session[:executing] = true      
      db.execute("UPDATE users SET state=? WHERE id=?", -1, @user_id)
      db.execute("UPDATE cards SET box_id=(SELECT id FROM boxes WHERE name=(SELECT sex FROM users WHERE id=?)) WHERE owner_id=?", @user_id, @user_id)
      session[:executing] = false
      json :status => "success"
    end
  end

  get "/card/re" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      json :status => "error"
    else
      loop do
        if session[:executing] == false then
          break
        end
        next
      end
      session[:executing] = true            
      state = db.execute("SELECT state FROM users WHERE id=?", @user_id)
      unless state[0][0] == -1 then
        session[:executing] = false
        return json :status => "error"
      end
      db.execute("UPDATE users SET state=? WHERE ID=?", 0, @user_id)
      db.execute("UPDATE cards SET box_id=? WHERE owner_id=?", 0, @user_id)
      session[:executing] = false      
      json :status => "success"
    end
  end

  get "/card/:sex/count" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      json :status => "error"
    else
      sex = params[:sex]
      count = db.execute("SELECT COUNT(id) FROM cards WHERE box_id=(SELECT id FROM boxes WHERE name=?) and  gainer_id=?", sex, 0)
      state = db.execute("SELECT state FROM users WHERE id=?", @user_id)
      json :status => "success", :count => count[0][0], :state => state[0][0]
    end    
  end

  get "/card/pull" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      json :status => "error"
    else
      loop do
        if @@pull_executing == false then
          break
        end
        next
      end
      @@pull_executing = true
      session[:executing] = true
      card_owner_id = db.execute("SELECT owner_id FROM cards WHERE gainer_id=?", @user_id)
      if  card_owner_id.empty? then
        current_user_username = db.execute("SELECT username FROM users WHERE id=?", @user_id)[0][0]
        sex_name = "male"
        user_sex = db.execute("SELECT sex FROM users WHERE id=?", @user_id)
        sex_name = "female" if user_sex[0][0] == "male"
        
        #users = db.execute("SELECT owner_id FROM cards WHERE box_id=(SELECT id FROM boxes WHERE name=?) and gainer_id=?", box_name, 0)
        users = db.execute("SELECT id FROM users WHERE sex=? AND state=?", sex_name, -1)
        unless users.empty? then
          random = Random.new
          index = random.rand(users.size)
          user_id = users[index][0]
          db.execute("UPDATE users SET state=? WHERE id=?", 1, @user_id)
          db.execute("UPDATE users SET state=? WHERE id=?", 1, user_id)
          db.execute("UPDATE cards SET gainer_id=? WHERE id=?", @user_id, user_id)          
          user_username = db.execute("SELECT username FROM users WHERE id=?", user_id)[0][0]          
          db.execute("INSERT INTO notifications (recipient_id, body, timestamp) VALUES (?, ?, DATETIME('NOW'))", user_id, "你被#{current_user_username}翻到了!")
          db.execute("INSERT INTO notifications (recipient_id, body, timestamp) VALUES (?, ?, DATETIME('NOW'))", @user_id, "你翻到了#{ user_username }!")
          username = db.execute("SELECT username FROM users WHERE id=?", user_id)

          session[:executing] = false          
          @@pull_executing = false
          return json :status => "success", :username => username
        end
      else
        session[:executing] = false                  
        @@pull_executing = false
        return json :status => "error"
      end
      session[:executing] = false          
      @@pull_executing = false
      return json :status => "error"
    end
  end

  get "/notifications/have" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      json :status => "error"      
    else
      notifications = db.execute("SELECT id FROM notifications WHERE recipient_id=? AND read=?", @user_id, 0)
      unless notifications.empty? then
        return json :status => "success", :notifications => "yes", :count => notifications.size
      end
      return json :status => "success", :notifications => "no"
    end
  end

  get "/notifications" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("signin")
    else
      @notifications = db.execute("SELECT body, timestamp FROM notifications WHERE recipient_id=? ORDER BY timestamp DESC", @user_id)
      unless @notifications.empty? then
        @notifications.size().times do |i|
          @notifications[i][1] = DateTime.parse(@notifications[i][1]).new_offset("+08:00").strftime("%H:%M")
        end
      end
      db.execute("UPDATE notifications SET read=? WHERE recipient_id=? and read=?", 1, @user_id, 0)
      @notifications_noread = db.execute("SELECT id FROM notifications WHERE recipient_id=? AND read=?", @user_id, 0)      
      erb :notifications
    end
  end

  get "/my" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("signin")
    else
      unless session[:update_status].nil? or session[:update_status].empty? then
        if session.delete(:update_status) == "error"
          @show_collapse = true
        end
      end
      @flash_message = session.delete(:flash_message)
      @user = db.execute("SELECT username, sex, state FROM users WHERE id=?", @user_id)[0]
      @notifications_noread = db.execute("SELECT id FROM notifications WHERE recipient_id=? AND read=?", @user_id, 0)      
      erb :my
    end
  end

  post "/my/update" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("signin")
    else
      session[:update_status] = "error"
      flash_message = ""
      if params["username"].nil? or params["username"].empty? or params["username"].gsub(/\s+/, "").empty? then
        flash_message = "用户名有误!"
      elsif params["password1"].nil? or params["password1"].empty? then
        flash_message = "密码有误!"
      elsif params["password2"].nil? or params["password2"].empty? then
        flash_message = "密码有误!"
      elsif params["password1"] != params["password2"] then
        flash_message = "输入的密码不一致!"
      elsif params["sex"].nil? or params["sex"].empty? then
        flash_message = "性别有误!"        
      else
        current_user_username = db.execute("SELECT username FROM users WHERE id=?", @user_id)[0][0]
        user_id = db.execute("SELECT id FROM users WHERE username=?", params["username"])
        if current_user_username != params["username"] and !user_id.empty? then
          flash_message = "用户名已经存在!"
        elsif params["sex"] == "male" or params["sex"] == "female" then
          db.execute("UPDATE users SET username=?, password=?, sex=? WHERE id=?", params["username"], params["password1"], params["sex"], @user_id)
          db.execute("UPDATE cards SET box_id=(SELECT id FROM boxes WHERE name=?) WHERE owner_id=? AND box_id != ?", params["sex"], @user_id, 0)          
          session[:update_status] = "success"
          flash_message = "修改成功!"        
        else
          flash_message = "性别有误!"            
        end
      end

      session[:flash_message] = flash_message
      redirect to("/my")
    end
  end

  get "/logout" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("signin")
    end
    
    session.delete(:user_id)
    session.delete(:executing)
    redirect to("/")
  end

  get "/action/:action" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      json :status => "error"      
    else
      loop do
        if session[:executing] == false then
          break
        end
        next
      end
      session[:executing] = true            
      user_state = db.execute("SELECT state FROM users WHERE id=?", @user_id)[0][0]
      current_user_username = db.execute("SELECT username FROM users WHERE id=?", @user_id)[0][0]
      card_owner_id = db.execute("SELECT owner_id FROM cards WHERE gainer_id=?", @user_id)
      if card_owner_id.empty? or user_state == 2 then
        session[:executing] = false            
        return json :status => "error"
      else
        body1 = ""
        body2 = ""
        card_owner_username = db.execute("SELECT username FROM users WHERE id=?", card_owner_id)[0][0]        
        if params[:action] == "sendtea" then
          body1 = "你送了#{card_owner_username}一杯五香茶!"
          body2 = "#{current_user_username}送了你一杯五香茶!"
        elsif params[:action] == "dating" then
          body1 = "你和#{card_owner_username}今晚相约! "
          body2 = "#{current_user_username}今晚约你! "
        end
        db.execute("INSERT INTO notifications (recipient_id, body, timestamp) VALUES (?, ?, DATETIME('NOW'))", @user_id, body1)
        db.execute("INSERT INTO notifications (recipient_id, body, timestamp) VALUES (?, ?, DATETIME('NOW'))", card_owner_id, body2)
        db.execute("UPDATE users SET state=? WHERE id=?", 2, @user_id)
        db.execute("UPDATE users SET state=? WHERE id=?", 2, card_owner_id)
        session[:executing] = false
        return json :status => "success"
      end
    end
  end

  get "/signup" do
    @user_id = session[:user_id]
    @flash_message = session.delete(:flash_message)
    unless @user_id.nil? then
      redirect to("/")
    end

    @no_login = true
    erb :signup
  end

  post "/signup" do
    @user_id = session[:user_id]
    unless @user_id.nil? then
      redirect to("/")
    else
      flash_message = ""
      if params["username"].nil? or params["username"].empty? or params["username"].gsub(/\s+/, "").empty? then
        flash_message = "用户名有误!"
      elsif params["password1"].nil? or params["password1"].empty? then
        flash_message = "密码有误!"
      elsif params["password2"].nil? or params["password2"].empty? then
        flash_message = "密码有误!"
      elsif params["password1"] != params["password2"] then
        flash_message = "输入的密码不一致!"
      elsif params["sex"].nil? or params["sex"].empty? then
        flash_message = "性别有误!"        
      else
        user2_id = db.execute("SELECT id FROM users WHERE username=?", params["username"])
        if !user2_id.empty? then
          flash_message = "用户名已经存在!"
        elsif params["sex"] == "male" or params["sex"] == "female" then
          db.execute("INSERT INTO users (username, password, sex) VALUES (?, ?, ?)", params["username"], params["password1"], params["sex"])
          user_id = db.execute("SELECT id FROM users WHERE username=? AND password=?", params["username"], params["password1"])
          db.execute("INSERT INTO cards (owner_id, box_id) VALUES (?, ?)", user_id, 0)
          session[:user_id] = user_id
          session[:executing] = false
          redirect to("/")
        else
          flash_message = "性别有误!"            
        end
      end

      session[:flash_message] = flash_message
      redirect to("/signup")
    end    
  end

  get "/ispulled" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      json :status => "error"
    else
      @card_box_id = db.execute("SELECT box_id FROM cards WHERE owner_id=?", @user_id)[0][0]
      unless @card_box_id == 0 then
        user_state = db.execute("SELECT state FROM users WHERE id=?", @user_id)[0][0]
        if user_state == 1 or user_state == 2 then
          return json :status => "success", :message => "yes"
        else
          return json :status => "success", :message => "no"          
        end
      end

      return json :status => "error"
    end
  end

  get "/admin" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("/")
    else
      user_role = db.execute("SELECT role FROM users WHERE id=?", @user_id)[0][0]
      if user_role == "admin" then
        @users = db.execute("SELECT id, username, sex, role FROM users")
        erb :admin, { :layout => :admin_layout }
      else
        status 403
      end
    end
  end

  post "/admin/user/delete" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("/")
    else
      user_role = db.execute("SELECT role FROM users WHERE id=?", @user_id)[0][0]
      if user_role == "admin" then
        unless params["user_id"].nil? or params["user_id"].empty? then
          user_ids = Array(params["user_id"])
          user_ids.each do |id|
            unless id == 1
              db.execute("DELETE FROM cards WHERE owner_id=?", id)
              db.execute("UPDATE users SET state=? WHERE id=(SELECT owner_id FROM cards WHERE gainer_id=?)", 0, id)
              db.execute("UPDATE cards SET gainer_id=? WHERE gainer_id=?", 0, id)
              db.execute("DELETE FROM notifications WHERE recipient_id=?", id)
              db.execute("DELETE FROM users WHERE id=?", id)
            end
          end
        end

        redirect to("/admin")
      else
        status 403
      end
    end    
  end

  get "/admin/user/add" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("/")
    else
      user_role = db.execute("SELECT role FROM users WHERE id=?", @user_id)[0][0]
      if user_role == "admin" then
        @flash_message = session.delete(:flash_message)        
        erb :admin_user, { :layout => :admin_layout }
      else
        status 403
      end
    end    
  end

  post "/admin/user/add" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("/")
    else
      user_role = db.execute("SELECT role FROM users WHERE id=?", @user_id)[0][0]
      if user_role == "admin" then
        flash_message = ""
        if params["username"].nil? or params["username"].empty? or params["username"].gsub(/\s+/, "").empty? then
          flash_message = "用户名有误!"
        elsif params["password1"].nil? or params["password1"].empty? then
          flash_message = "密码有误!"
        elsif params["password2"].nil? or params["password2"].empty? then
          flash_message = "密码有误!"
        elsif params["password1"] != params["password2"] then
          flash_message = "输入的密码不一致!"
        elsif params["sex"].nil? or params["sex"].empty? then
          flash_message = "性别有误!"        
        else
          user2_id = db.execute("SELECT id FROM users WHERE username=?", params["username"])
          if !user2_id.empty? then
            flash_message = "用户名已经存在!"
          elsif params["sex"] == "male" or params["sex"] == "female" then
            db.execute("INSERT INTO users (username, password, sex) VALUES (?, ?, ?)", params["username"], params["password1"], params["sex"])
            user_id = db.execute("SELECT id FROM users WHERE username=? AND password=?", params["username"], params["password1"])
            db.execute("INSERT INTO cards (owner_id, box_id) VALUES (?, ?)", user_id, 0)
            redirect to("/admin")
          else
            flash_message = "性别有误!"            
          end
        end

        session[:flash_message] = flash_message
        redirect to("/admin/user/add")
      else
        status 403
      end
    end
  end

  get "/admin/user/:uid/edit" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("/")
    else
      user_role = db.execute("SELECT role FROM users WHERE id=?", @user_id)[0][0]
      if user_role == "admin" then
        @user = db.execute("SELECT username, password, sex FROM users WHERE id=?", params[:uid].to_i)
        if @user.empty? then
          redirect to("/admin")
        else
          @user = @user[0]
        end
        @flash_message = session.delete(:flash_message)        
        erb :admin_user, { :layout => :admin_layout }
      else
        status 403
      end
    end            
  end

  post "/admin/user/:uid/edit" do
    @user_id = session[:user_id]
    if @user_id.nil? then
      redirect to("/")
    else
      user_role = db.execute("SELECT role FROM users WHERE id=?", @user_id)[0][0]
      if user_role == "admin" then
        edit_user_username = db.execute("SELECT username FROM users WHERE id=?", params[:uid].to_i)[0][0]
        if edit_user_username.empty? then
          redirect to("/admin")
        else
          flash_message = ""
          if params["username"].nil? or params["username"].empty? or params["username"].gsub(/\s+/, "").empty? then
            flash_message = "用户名有误!"
          elsif params["password1"].nil? or params["password1"].empty? then
            flash_message = "密码有误!"
          elsif params["password2"].nil? or params["password2"].empty? then
            flash_message = "密码有误!"
          elsif params["password1"] != params["password2"] then
            flash_message = "输入的密码不一致!"
          elsif params["sex"].nil? or params["sex"].empty? then
            flash_message = "性别有误!"        
          else
            user2_id = db.execute("SELECT id FROM users WHERE username=?", params["username"])
            if edit_user_username != params["username"] and !user2_id.empty? then
              flash_message = "用户名已经存在!"
            elsif params["sex"] == "male" or params["sex"] == "female" then
              db.execute("UPDATE users SET username=?, password=?, sex=? WHERE id=?", params["username"], params["password1"], params["sex"], params[:uid].to_i)
              db.execute("UPDATE cards SET box_id=(SELECT id FROM boxes WHERE name=?) WHERE owner_id=? AND box_id != ?", params["sex"], params[:uid], 0)
              redirect to("/admin")
            else
              flash_message = "性别有误!"
            end
          end
        end
        
        session[:flash_message] = flash_message
        redirect to("/admin/user/#{params[:uid]}/edit")        
      else
        status 403
      end
    end            
  end
end
