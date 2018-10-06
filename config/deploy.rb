set :application, "turl"
set :repository,  "."

set :scm, :git

set :deploy_via, :copy
set :copy_strategy, :export

role :app, "your app-server here"
role :web, "your web-server here"
role :db,  "your db-server here", :primary => true

namespace :deploy do
  task :post_setup do
    sudo "mkdir -p #{deploy_to}/#{shared_dir}/db"
    sudo "chgrp -R www-data #{deploy_to}/#{shared_dir}/db"
    sudo "chgrp -R www-data #{shared_path}/log"
  end

  task :link_db do
    # Link in the database
    run "ln -nfs #{shared_path}/db/turl.db #{current_release}/turl.db"
  end

  task :restart do
    run "touch #{current_path}/tmp/restart.txt"
  end
end

after "deploy:update_code", "deploy:link_db"
