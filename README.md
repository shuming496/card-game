# card-game
## 首先安装Git、Ruby、Sqlite、Nginx、Bundler、screen

**Centos**

    sudo yum -y install git sqlite sqlite-devel ruby nginx screen
    
    gem install bundler

**Ubuntu**

    sudo apt-get -y install git sqlite3 libsqlite3-dev ruby nginx screen
    
    gem install bundler
    

## 把源代码克隆到本地，安装依赖并初始化数据库
	cd /var/www
	
    git clone git@github.com:shuming496/card-game.git

	cd card-game

    bundle install 
    
	bundle exec ruby init_db.rb

## 配置Nginx
**把以下内容保存为 card-game.conf 到 /etc/nginx/sites-enabled/ 目录下**
	
    server {
	    listen 80;
	    # 修改访问域名
	    server_name www.example.org;

	    access_log /var/log/card_access.log;
	    error_log /var/log/card_error.log;

	    location / {
	        proxy_pass http://localhost:9292;
	        # proxy_redirect off;
	        proxy_set_header Host $host;
	        proxy_set_header X-Real-IP $remote_addr;
	        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	        client_max_body_size 100M;
	    }

	}

## 启动程序

**由于程序在控制台运行，所以要用到 screen 工具。这样可以放心的退出控制台而不尽担心程序自动停止**

    screen
    
	systemctl enable nginx
	
	systemctl restart nginx

    cd /var/www/card-game

	bundle exec rackup

## 结束程序

    screen -ls

**会获得类似这样的输出**

    There is a screen on:
    	7347.pts-0.card-game	(02/18/19 13:03:19)	(Detached)

**输入命令**

    screen -r 7347

**回到原来控制台后，键入Ctrl+c即可**
