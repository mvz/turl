set :application, "turl"
set :repository,  "."

set :scm, :git

set :deploy_via, :copy
set :copy_strategy, :export

role :app, "your app-server here"
role :web, "your web-server here"
role :db,  "your db-server here", :primary => true

namespace :deploy do
  task :link_db do
    # Link in the database 
    run "ln -nfs #{shared_path}/turl.db #{current_release}/turl.db" 
  end

  task :restart do
    run "touch #{current_path}/tmp/restart.txt"
  end
end

after "deploy:update_code", "deploy:link_db"
