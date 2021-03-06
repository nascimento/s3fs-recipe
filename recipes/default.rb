#
# Cookbook Name:: s3fs
# Recipe:: default
#
# Copyright (C) 2011 Tom Wilson
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

node['s3fs']['packages'].each do |pkg|
  package pkg
end

if not node['s3fs']['packages'].include?("fuse")
  # install fuse
  remote_file "#{Chef::Config[:file_cache_path]}/fuse-#{ node['fuse']['version'] }.tar.gz" do
    source "http://downloads.sourceforge.net/project/fuse/fuse-2.X/#{ node['fuse']['version'] }/fuse-#{ node['fuse']['version'] }.tar.gz"
    mode 0644
    action :create_if_missing
  end

  bash "install fuse" do
    cwd Chef::Config[:file_cache_path]
    code "
      tar zxvf fuse-#{ node['fuse']['version'] }.tar.gz
      cd fuse-#{ node['fuse']['version'] }
      ./configure --prefix=/usr
      make
      make install
    "

    not_if { File.exists?("/usr/bin/fusermount") }
  end

end

if %w{centos redhat amazon}.include?(node['platform'])
  template "/etc/ld.so.conf.d/s3fs.conf" do
    source "s3fs.conf.erb"
    owner "root"
    group "root"
    mode 0644
  end

  bash "ldconfig" do
    code "ldconfig"
    only_if { `ldconfig -v | grep fuse | wc -l` == 0 }
  end
end

remote_file "#{Chef::Config[:file_cache_path]}/s3fs-#{ node['s3fs']['version'] }.tar.gz" do
  source "http://s3fs.googlecode.com/files/s3fs-#{ node['s3fs']['version'] }.tar.gz"
  mode 0644
  action :create_if_missing
end

bash "install s3fs" do
  cwd Chef::Config[:file_cache_path]
  code "
    export PKG_CONFIG_PATH=/usr/lib/pkgconfig:/usr/lib64/pkgconfig
    tar zxvf s3fs-#{ node['s3fs']['version'] }.tar.gz
    cd s3fs-#{ node['s3fs']['version'] }
    ./configure --prefix=/usr
    make
    make install
  "

  not_if { File.exists?("/usr/bin/s3fs") }
end

def retrieve_s3_buckets(s3_data)
  buckets = []

  s3_data['buckets'].each do |bucket|
    bucket = Bucket.new(bucket, node)
    buckets << {
      :name => bucket.name,
      :path => bucket.path,
      :access_key => s3_data['access_key_id'],
      :secret_key => s3_data['secret_access_key']
    }
  end

  buckets
end

class Bucket
  attr_reader :name
  attr_reader :path

  def initialize bucket, node
    if bucket.is_a? String
      @name = bucket
      @path = File.join(node['s3fs']['mount_root'], @name)
    elsif bucket.is_a? Hash
      @name = bucket['name']
      @path = bucket['path']
    else
      @name = ""
      @path = ""
    end
  end
end

if node['s3fs']['multi_user']
  buckets = []
  node['s3fs']['data'].each do |item|
    buckets += retrieve_s3_buckets(item)
  end
else
  buckets = retrieve_s3_buckets(node['s3fs']['data'])
end

template "/etc/passwd-s3fs" do
  source "passwd-s3fs.erb"
  owner "root"
  group "root"
  mode 0600
  variables(:buckets => buckets)
end

buckets.each do |bucket|
  directory bucket[:path] do
    owner     "root"
    group     "root"
    mode      0777
    recursive true
    not_if do
      File.exists?(bucket[:path])
    end
  end

  mount bucket[:path] do
    device "s3fs##{bucket[:name]}"
    fstype "fuse"
    options node['s3fs']['options']
    dump 0
    pass 0
    action [:enable, :mount]
    not_if "grep -qs '#{bucket[:path]} ' /proc/mounts"
  end
end
