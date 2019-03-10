# coding: utf-8
# app.rb
require 'sinatra'
require 'sinatra/json'
require 'erb'
require 'rufus-scheduler'
require 'sqlite3'
require 'i18n'
require 'i18n/backend/fallbacks'
require 'date'

class App < Sinatra::Base
  # Pull execute lock
  @@pull_executing = false

  # Pull flag
  @@can_pull = false

  # New database object
  db = SQLite3::Database.new 'db/database.db'

  I18n::Backend::Simple.send(:include, I18n::Backend::Fallbacks)
  I18n.load_path = Dir[File.join(settings.root, 'locales', '*.yml')]
  I18n.backend.load_translations

  enable :sessions

  before do
    session[:user_lang] = params[:lang] unless params[:lang].nil?
    begin
      if session[:user_lang].nil?
        I18n.locale = request.env['HTTP_ACCEPT_LANGUAGE'][0, 2]
      else
        I18n.locale = session[:user_lang]
        user_id = session[:user_id]
        unless user_id.nil?
          db.execute('UPDATE users SET language=? 
                      WHERE id=?', session[:user_lang], user_id)
        end
      end
    rescue I18n::InvalidLocale => ex
      I18n.locale = :en      
    end
  end

  scheduler = Rufus::Scheduler.new

  ENV['TZ'] = 'Asia/Shanghai'
  scheduler.cron '0 0 * * *' do
    db.execute('UPDATE users SET state=? WHERE state=? OR state=?', 0, 1, 2)
    db.execute('UPDATE cards SET gainer_id=?, box_id=?
                WHERE gainer_id != ?', 0, 0, 0)
    db.execute('DELETE FROM notifications')
  end

  scheduler.cron '00 22 * * *' do
    @@can_pull = false
  end  

  scheduler.cron '00 20 * * *' do
    @@can_pull = true
    ids = db.execute('SELECT id FROM users WHERE id!=?', 1)
    current_user_lang = I18n.locale
    ids.each do |id|
      user_lang = db.execute('SELECT language FROM users WHERE id=?', id)[0][0]
      I18n.locale = user_lang
      
      db.execute("INSERT INTO notifications(recipient_id, body, timestamp)
                  VALUES (?, ?, DATETIME('NOW'))",
                  id[0], I18n.t('notification.time_for_showdown'))
    end
    I18n.locale = current_user_lang
  end

  get '/' do
    @user_id = session[:user_id]
    if @user_id.nil?
      redirect to('/signin')
    else
      @user_username = db.execute('SELECT username FROM users
                                   WHERE id=?', @user_id)[0][0]
      @user_username2 = db.execute('SELECT username2 FROM users 
                                    WHERE id=?', @user_id)[0][0]
      @user_sex = db.execute('SELECT sex FROM users WHERE id=?', @user_id)[0][0]
      @user_state = db.execute('SELECT state FROM users
                                WHERE id=?', @user_id)[0][0]
      @card_owner_id = db.execute('SELECT owner_id FROM cards
                                   WHERE gainer_id=?', @user_id)
      unless @card_owner_id.empty?
        @card_owner_username = db.execute('SELECT username FROM users
                                           WHERE id=?', @card_owner_id)[0][0]
        @card_owner_username2 = db.execute('SELECT username2 FROM users
                                           WHERE id=?', @card_owner_id)[0][0]
      end
      @card_box_id = db.execute('SELECT box_id FROM cards
                                 WHERE owner_id=?', @user_id)[0][0]
      @card_male_count = db.execute('SELECT COUNT(id) FROM cards
                                     WHERE box_id=(SELECT id FROM boxes WHERE name=?)
                                     AND gainer_id=?', 'male', 0)[0][0]
      @card_female_count = db.execute('SELECT COUNT(id) FROM cards
                                       WHERE box_id=(SELECT id FROM boxes WHERE name=?)
                                       AND gainer_id=?', 'female', 0)[0][0]
      @notifications_noread = db.execute('SELECT id FROM notifications
                                          WHERE recipient_id=?
                                          AND read=?', @user_id, 0)

      @can_pull = @@can_pull

      erb :index
    end
  end

  get '/signin' do
    @user_id = session[:user_id]

    unless @user_id.nil?
      db.execute('UPDATE users SET language=? 
                      WHERE id=?', I18n.locale.to_s, @user_id)
      redirect to('/')
    end

    @no_login = true
    
    erb :signin
  end

  post '/signin' do
    @user_id = session[:user_id]

    redirect to('/') unless @user_id.nil?

    username = params['username']
    password = params['password']

    user_id = db.execute('SELECT id FROM users
                          WHERE username=? AND password=?', username, password)

    if user_id.empty?
      @flash_message = I18n.t('form.username_or_password_is_incorrect')
      @no_login = true
      
      erb :signin
    else
      session[:user_id] = user_id
      session[:executing] = false

      db.execute('UPDATE users SET language=? 
                      WHERE id=?', I18n.locale.to_s, user_id)
      
      redirect to('/')
    end
  end

  get '/card/push' do
    @user_id = session[:user_id]

    if @user_id.nil?
      json status: 'error'
    else
      loop do
        break if session[:executing] == false

        next
      end

      session[:executing] = true

      db.execute('UPDATE users SET state=? WHERE id=?', -1, @user_id)
      db.execute('UPDATE cards SET box_id=(SELECT id FROM boxes
                  WHERE name=(SELECT sex FROM users WHERE id=?))
                  WHERE owner_id=?', @user_id, @user_id)

      session[:executing] = false

      json status: 'success'
    end
  end

  get '/card/re' do
    @user_id = session[:user_id]

    if @user_id.nil?
      json status: 'error', message: 'auth error'
    else
      loop do
        break if session[:executing] == false
        
        next
      end

      session[:executing] = true
      state = db.execute('SELECT state FROM users WHERE id=?', @user_id)

      unless state[0][0] == -1
        session[:executing] = false
        return json status: 'error'
      end

      db.execute('UPDATE users SET state=? WHERE ID=?', 0, @user_id)
      db.execute('UPDATE cards SET box_id=? WHERE owner_id=?', 0, @user_id)

      session[:executing] = false

      json status: 'success'
    end
  end

  get '/card/:sex/count' do
    @user_id = session[:user_id]

    if @user_id.nil?
      json status: 'error', message: 'auth error'
    else
      sex = params[:sex]

      if (sex == 'male') || (sex == 'female')
        count = db.execute('SELECT COUNT(id) FROM cards
                            WHERE box_id=(SELECT id FROM boxes WHERE name=?)
                            AND gainer_id=?', sex, 0)
        state = db.execute('SELECT state FROM users WHERE id=?', @user_id)

        json status: 'success', count: count[0][0],
             state: state[0][0], can_pull: @@can_pull.to_s
      else
        json status: 'error', message: 'type error'
      end
    end
  end

  get '/card/pull' do
    @user_id = session[:user_id]

    if @user_id.nil? || (@@can_pull == false)
      json status: 'error', message: 'auth error or refuse action'
    else
      loop do
        break if @@pull_executing == false
        
        next
      end

      @@pull_executing = true
      session[:executing] = true
      card_owner_id = db.execute('SELECT owner_id FROM cards
                                  WHERE gainer_id=?', @user_id)

      if card_owner_id.empty?
        current_user_username = db.execute('SELECT username FROM users
                                            WHERE id=?', @user_id)[0][0]
        sex_name = 'male'
        user_sex = db.execute('SELECT sex FROM users
                               WHERE id=?', @user_id)
        sex_name = 'female' if user_sex[0][0] == 'male'
        users = db.execute('SELECT id FROM users
                            WHERE sex=? AND state=?', sex_name, -1)

        unless users.empty?
          random = Random.new
          index = random.rand(users.size)
          user_id = users[index][0]

          db.execute('UPDATE users SET state=? WHERE id=?', 1, @user_id)
          db.execute('UPDATE users SET state=? WHERE id=?', 1, user_id)
          db.execute('UPDATE cards SET gainer_id=?
                      WHERE id=?', @user_id, user_id)
          user_username = db.execute('SELECT username FROM users
                                      WHERE id=?', user_id)[0][0]

          you_have_been_pulled_by = ''
          to_user_lang = db.execute('SELECT language FROM users 
                                     WHERE id=?', user_id)[0][0]
          current_user_lang = I18n.locale
          I18n.locale = to_user_lang
          you_have_been_pulled_by = I18n.t('notification.you_have_been_pulled_by').
                              gsub(/{}/, "#{current_user_username}")
          I18n.locale = current_user_lang

          db.execute("INSERT INTO notifications (recipient_id, body, timestamp)
                      VALUES (?, ?, DATETIME('NOW'))",
                     user_id, you_have_been_pulled_by)
          db.execute("INSERT INTO notifications (recipient_id, body, timestamp)
                      VALUES (?, ?, DATETIME('NOW'))",
                     @user_id, I18n.t('notification.you_have_pulled').
                                 gsub(/{}/, "#{user_username}"))
          username = db.execute('SELECT username FROM users WHERE id=?', user_id)

          session[:executing] = false
          @@pull_executing = false

          return json status: 'success', username: username
        end
      else
        session[:executing] = false
        @@pull_executing = false

        return json status: 'error'
      end
      session[:executing] = false
      @@pull_executing = false

      return json status: 'error'
    end
  end

  get '/notifications/have' do
    @user_id = session[:user_id]

    if @user_id.nil?
      json status: 'error', message: 'auth error'
    else
      notifications = db.execute('SELECT id FROM notifications
                                  WHERE recipient_id=?
                                  AND read=?', @user_id, 0)

      unless notifications.empty?
        return json status: 'success',
                    notifications: 'yes',
                    count: notifications.size
      end

      return json status: 'success', notifications: 'no'
    end
  end

  get '/notifications' do
    @user_id = session[:user_id]

    if @user_id.nil?
      redirect to('signin')
    else
      @notifications = db.execute('SELECT body, timestamp FROM notifications
                                   WHERE recipient_id=?
                                   ORDER BY timestamp DESC', @user_id)

      unless @notifications.empty?
        @notifications.size.times do |i|
          @notifications[i][1] = DateTime.parse(@notifications[i][1])
                                   .new_offset('+08:00').strftime('%H:%M')
        end
      end

      db.execute('UPDATE notifications SET read=?
                  WHERE recipient_id=?
                  AND read=?', 1, @user_id, 0)
      
      @notifications_noread = db.execute('SELECT id FROM notifications
                                          WHERE recipient_id=?
                                          AND read=?', @user_id, 0)

      erb :notifications
    end
  end

  get '/my' do
    @user_id = session[:user_id]

    if @user_id.nil?
      redirect to('signin')
    else
      unless session[:update_status].nil? || session[:update_status].empty?
        @show_collapse = true if session.delete(:update_status) == 'error'
      end

      @flash_message = session.delete(:flash_message)
      @user = db.execute('SELECT username, sex, state FROM users
                          WHERE id=?', @user_id)[0]
      @notifications_noread = db.execute('SELECT id FROM notifications
                                          WHERE recipient_id=?
                                          AND read=?', @user_id, 0)

      erb :my
    end
  end

  post '/my/update' do
    @user_id = session[:user_id]

    if @user_id.nil?
      redirect to('signin')
    else
      session[:update_status] = 'error'
      flash_message = ''

      if params['username'].nil? || params['username'].empty? ||
         params['username'].gsub(/\s+/, '').empty?
        flash_message = I18n.t('form.username_is_incorrect')
      elsif params['password1'].nil? || params['password1'].empty?
        flash_message = I18n.t('form.password_is_incorrect')
      elsif params['password2'].nil? || params['password2'].empty?
        flash_message = I18n.t('form.password_is_incorrect')
      elsif params['password1'] != params['password2']
        flash_message = I18n.t('form.enter_the_password_twice_inconsistent')
      elsif params['sex'].nil? || params['sex'].empty?
        flash_message = I18n.t('form.sex_is_incorrect')
      else
        current_user_username = db.execute('SELECT username FROM users
                                            WHERE id=?', @user_id)[0][0]
        user_id = db.execute('SELECT id FROM users
                              WHERE username=?', params['username'])

        if (current_user_username != params['username']) && !user_id.empty?
          flash_message = I18n.t('form.username_already_exists')
        elsif (params['sex'] == 'male') || (params['sex'] == 'female')
          db.execute('UPDATE users SET username=?, password=?, sex=? WHERE id=?',
                     params['username'], params['password1'],
                     params['sex'], @user_id)
          db.execute('UPDATE cards SET box_id=(SELECT id FROM boxes WHERE name=?)
                      WHERE owner_id=? AND box_id != ?',
                     params['sex'], @user_id, 0)

          session[:update_status] = 'success'
          flash_message = I18n.t('form.modified_successfully')
        else
          flash_message = I18n.t('form.sex_is_incorrect')
        end
      end

      session[:flash_message] = flash_message

      redirect to('/my')
    end
  end

  get '/logout' do
    @user_id = session[:user_id]

    redirect to('signin') if @user_id.nil?

    session.delete(:user_id)
    session.delete(:executing)
    session.delete(:user_lang)

    redirect to('/')
  end

  get '/action/:action' do
    @user_id = session[:user_id]

    if @user_id.nil?
      json status: 'error'
    else
      loop do
        break if session[:executing] == false

        next
      end

      session[:executing] = true
      user_state = db.execute('SELECT state FROM users
                               WHERE id=?', @user_id)[0][0]
      current_user_username = db.execute('SELECT username FROM users
                                          WHERE id=?', @user_id)[0][0]
      card_owner_id = db.execute('SELECT owner_id FROM cards
                                  WHERE gainer_id=?', @user_id)

      if card_owner_id.empty? || (user_state == 2)
        session[:executing] = false
        return json status: 'error'
      else
        body1 = ''
        body2 = ''
        card_owner_username = db.execute('SELECT username FROM users
                                          WHERE id=?', card_owner_id)[0][0]

        if params[:action] == 'sendtea'
          body1 = I18n.t('notification.you_have_served_a_cup_of_tea').
                    gsub(/{}/, "#{card_owner_username}")
          
          body2 = ''
          to_user_lang = db.execute('SELECT language FROM users 
                                     WHERE id=?', card_owner_id)[0][0]
          current_user_lang = I18n.locale
          I18n.locale = to_user_lang
          body2 = I18n.t('notification.has_served_you_a_cap_of_tea').
                    gsub(/{}/, "#{current_user_username}")
          I18n.locale = current_user_lang
          
        elsif params[:action] == 'dating'
          body1 = I18n.t('notification.you_have_a_date_with').
                    gsub(/{}/, "#{card_owner_username}")

          body2 = ''
          to_user_lang = db.execute('SELECT language FROM users 
                                     WHERE id=?', card_owner_id)[0][0]
          current_user_lang = I18n.locale
          I18n.locale = to_user_lang
          body2 = I18n.t('notification.has_a_date_with_you').
                    gsub(/{}/, "#{current_user_username}")
          I18n.locale = current_user_lang
          
        end

        db.execute("INSERT INTO notifications (recipient_id, body, timestamp)
                    VALUES (?, ?, DATETIME('NOW'))", @user_id, body1)
        db.execute("INSERT INTO notifications (recipient_id, body, timestamp)
                    VALUES (?, ?, DATETIME('NOW'))", card_owner_id, body2)
        db.execute('UPDATE users SET state=? WHERE id=?', 2, @user_id)
        db.execute('UPDATE users SET state=? WHERE id=?', 2, card_owner_id)

        session[:executing] = false

        return json status: 'success'
      end
    end
  end

  get '/signup' do
    @user_id = session[:user_id]
    @flash_message = session.delete(:flash_message)

    unless @user_id.nil?
      db.execute('UPDATE users SET language=? 
                      WHERE id=?', I18n.locale.to_s, @user_id)
      redirect to('/')
    end

    @no_login = true

    erb :signup
  end

  post '/signup' do
    @user_id = session[:user_id]

    if @user_id.nil?
      flash_message = ''
      if params['username'].nil? || params['username'].empty? ||
         params['username'].gsub(/\s+/, '').empty?
        flash_message = I18n.t('form.username_is_incorrect')
      elsif params['password1'].nil? || params['password1'].empty?
        flash_message = I18n.t('form.password_is_incorrect')
      elsif params['password2'].nil? || params['password2'].empty?
        flash_message = I18n.t('form.password_is_incorrect')
      elsif params['password1'] != params['password2']
        flash_message = I18n.t('form.enter_the_password_twice_inconsistent')
      elsif params['sex'].nil? || params['sex'].empty?
        flash_message = I18n.t('form.sex_is_incorrect')
      else
        user2_id = db.execute('SELECT id FROM users
                               WHERE username=?', params['username'])
        if !user2_id.empty?
          flash_message = I18n.t('form.username_already_exists')
        elsif (params['sex'] == 'male') || (params['sex'] == 'female')
          db.execute('INSERT INTO users (username, password, sex) 
                      VALUES (?, ?, ?)',
                      params['username'], params['password1'], params['sex'])
          user_id = db.execute('SELECT id FROM users 
                                WHERE username=? AND password=?',
                                params['username'], params['password1'])
          db.execute('INSERT INTO cards (owner_id, box_id) 
                      VALUES (?, ?)', user_id, 0)

          session[:user_id] = user_id
          session[:executing] = false

          db.execute('UPDATE users SET language=? 
                      WHERE id=?', I18n.locale.to_s, user_id)

          redirect to('/')
        else
          flash_message = I18n.t('form.sex_is_incorrect')
        end
      end

      session[:flash_message] = flash_message

      redirect to('/signup')
    else
      redirect to('/')
    end
  end

  get '/ispulled' do
    @user_id = session[:user_id]

    if @user_id.nil?
      json status: 'error'
    else
      @card_box_id = db.execute('SELECT box_id FROM cards
                                 WHERE owner_id=?', @user_id)[0][0]

      unless @card_box_id == 0
        user_state = db.execute('SELECT state FROM users
                                 WHERE id=?', @user_id)[0][0]

        if (user_state == 1) || (user_state == 2)
          return json status: 'success', message: 'yes'
        else
          return json status: 'success', message: 'no'
        end
      end

      return json status: 'success', message: 'no'
    end
  end

  get '/admin' do
    @user_id = session[:user_id]

    if @user_id.nil?
      redirect to('/')
    else
      user_role = db.execute('SELECT role FROM users WHERE id=?', @user_id)[0][0]

      if user_role == 'admin'
        @users = db.execute('SELECT id, username, username2, sex, role 
                             FROM users')
        erb :admin, layout: :admin_layout
      else
        status 403
      end
    end
  end

  post '/admin/user/delete' do
    @user_id = session[:user_id]

    if @user_id.nil?
      redirect to('/')
    else
      user_role = db.execute('SELECT role FROM users WHERE id=?', @user_id)[0][0]

      if user_role == 'admin'
        unless params['user_id'].nil? || params['user_id'].empty?
          user_ids = Array(params['user_id'])

          user_ids.each do |id|
            next if id == 1

            db.execute('DELETE FROM cards WHERE owner_id=?', id)
            db.execute('UPDATE users SET state=?
                        WHERE id=(SELECT owner_id FROM cards
                        WHERE gainer_id=?)', 0, id)
            db.execute('UPDATE cards SET gainer_id=? WHERE gainer_id=?', 0, id)
            db.execute('DELETE FROM notifications WHERE recipient_id=?', id)
            db.execute('DELETE FROM users WHERE id=?', id)
          end
        end

        redirect to('/admin')
      else
        status 403
      end
    end
  end

  get '/admin/user/add' do
    @user_id = session[:user_id]

    if @user_id.nil?
      redirect to('/')
    else
      user_role = db.execute('SELECT role FROM users WHERE id=?', @user_id)[0][0]

      if user_role == 'admin'
        @flash_message = session.delete(:flash_message)

        erb :admin_user, layout: :admin_layout
      else
        status 403
      end
    end
  end

  post '/admin/user/add' do
    @user_id = session[:user_id]

    if @user_id.nil?
      redirect to('/')
    else
      user_role = db.execute('SELECT role FROM users WHERE id=?', @user_id)[0][0]

      if user_role == 'admin'
        flash_message = ''
        if params['username'].nil? || params['username'].empty? ||
           params['username'].gsub(/\s+/, '').empty?
          flash_message = '用户名有误!'
        elsif params['password1'].nil? || params['password1'].empty?
          flash_message = '密码有误!'
        elsif params['password2'].nil? || params['password2'].empty?
          flash_message = '密码有误!'
        elsif params['password1'] != params['password2']
          flash_message = '输入的密码不一致!'
        elsif params['sex'].nil? || params['sex'].empty?
          flash_message = '性别有误!'
        else
          user2_id = db.execute('SELECT id FROM users WHERE username=?',
                                params['username'])
          if !user2_id.empty?
            flash_message = '用户名已经存在!'
          elsif (params['sex'] == 'male') || (params['sex'] == 'female')
            db.execute('INSERT INTO users (username, username2, password, sex)
                        VALUES (?, ?, ?, ?)',
                       params['username'], params['username2'],
                       params['password1'], params['sex'])
            user_id = db.execute('SELECT id FROM users
                                  WHERE username=? AND password=?',
                                 params['username'], params['password1'])

            db.execute('INSERT INTO cards (owner_id, box_id)
                        VALUES (?, ?)', user_id, 0)

            redirect to('/admin')
          else
            flash_message = '性别有误!'
          end
        end

        session[:flash_message] = flash_message

        redirect to('/admin/user/add')
      else
        status 403
      end
    end
  end

  get '/admin/user/:uid/edit' do
    @user_id = session[:user_id]

    if @user_id.nil?
      redirect to('/')
    else
      user_role = db.execute('SELECT role FROM users WHERE id=?', @user_id)[0][0]

      if user_role == 'admin'
        @user = db.execute('SELECT username, username2, password, sex FROM users
                            WHERE id=?', params[:uid].to_i)

        if @user.empty?
          redirect to('/admin')
        else
          @user = @user[0]
        end
        @flash_message = session.delete(:flash_message)

        erb :admin_user, layout: :admin_layout
      else
        status 403
      end
    end
  end

  post '/admin/user/:uid/edit' do
    @user_id = session[:user_id]

    if @user_id.nil?
      redirect to('/')
    else
      user_role = db.execute('SELECT role FROM users WHERE id=?', @user_id)[0][0]

      if user_role == 'admin'
        edit_user_username = db.execute('SELECT username FROM users
                                         WHERE id=?', params[:uid].to_i)[0][0]

        if edit_user_username.empty?
          redirect to('/admin')
        else
          flash_message = ''
          if params['username'].nil? || params['username'].empty? ||
             params['username'].gsub(/\s+/, '').empty?
            flash_message = '用户名有误!'
          elsif params['password1'].nil? || params['password1'].empty?
            flash_message = '密码有误!'
          elsif params['password2'].nil? || params['password2'].empty?
            flash_message = '密码有误!'
          elsif params['password1'] != params['password2']
            flash_message = '输入的密码不一致!'
          elsif params['sex'].nil? || params['sex'].empty?
            flash_message = '性别有误!'
          else
            user2_id = db.execute('SELECT id FROM users WHERE username=?',
                                  params['username'])
            if (edit_user_username != params['username']) && !user2_id.empty?
              flash_message = '用户名已经存在!'
            elsif (params['sex'] == 'male') || (params['sex'] == 'female')
              db.execute('UPDATE users 
                          SET username=?, username2=?, password=?, sex=?
                          WHERE id=?',
                         params['username'], params['username2'],
                         params['password1'],
                         params['sex'], params[:uid].to_i)
              db.execute('UPDATE cards 
                          SET box_id=(SELECT id FROM boxes WHERE name=?)
                          WHERE owner_id=? AND box_id != ?',
                         params['sex'], params[:uid], 0)

              redirect to('/admin')
            else
              flash_message = '性别有误!'
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
