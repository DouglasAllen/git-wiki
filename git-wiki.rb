#!/usr/bin/ruby

require 'rubygems'
require 'sinatra'
require 'grit'
require 'redcloth'

module GitWiki
  class << self
    attr_accessor :wiki_path, :root_page, :extension, :link_pattern
    attr_reader :wiki_name, :repository
    def wiki_path=(path)
      @wiki_name = File.basename(path)
      @repository = Grit::Repo.new(path)
    end
  end 
end

def all_files(repo, files=[], basedir="")
  contents = Array === repo ? repo : repo.contents
  folders, blobs = contents.partition { |e| Grit::Tree === e }
  blobs.each { |e| files << "#{basedir}#{e.name}" }
  folders.each do |f|
    base = "#{basedir}#{f.name}/"
    all_files(f.contents, files, base)
  end

  return files
end

class Page

  def self.find_all(path=nil)
    commit = GitWiki.repository.commit(GitWiki.repository.head.commit)
    tree = GitWiki.repository.tree 
    tree = tree / path if path

    all_files(tree).map do |e| 
      new(commit, "#{path}#{e}")
    end


    #GitWiki.repository.tree.contents.select do |blob|
    #  blob.name =~ /#{GitWiki.extension}$/
    #end.collect do |blob|
    #  new(blob)
    #end
  end

  def self.find_or_create(name, rev=nil)
    path = name + GitWiki.extension
    commit = GitWiki.repository.commit(rev || GitWiki.repository.head.commit)
    new(commit, path)
  end

  def self.wikify(content)
    content.gsub(GitWiki.link_pattern) {|match| link($1) }
  end

  def self.link(text)
    page = find_or_create(text.gsub(%r{[^\w\s/]}, '').split.join('-').downcase)
    "<a class='page #{page.css_class}' href='#{page.url}'>#{text}</a>"
  end

  def initialize(commit_or_blob, path=nil)
    unless path
      @blob = commit_or_blob
    else
      @commit = commit_or_blob
      @path   = path
      @blob   = commit_or_blob.tree/path || Grit::Blob.create(GitWiki.repository, :name => path)
    end
  end

  def to_s
    @path.sub(/#{GitWiki.extension}$/, '')
  end

  def url
    to_s == GitWiki.root_page ? '/' : "/pages/#{to_s}"
  end

  def edit_url
    "/pages/#{to_s}/edit"
  end

  def log_url
    "/pages/#{to_s}/revisions/"
  end

  def css_class
    @blob.id ? 'existing' : 'new'
  end

  def content
    @blob.data
  end

  def to_html
    Page.wikify(RedCloth.new(content).to_html)
  end

  def log
    head = GitWiki.repository.head.name
    GitWiki.repository.log(head, @blob.name).collect do |commit|
      commit.to_hash
    end
  end

  def save!(data, msg)
    msg = "web commit: #{self}" if msg.empty?
    Dir.chdir(GitWiki.repository.working_dir) do
      File.open(@path, 'w') {|f| f.puts(data.gsub("\r\n", "\n")) }
      GitWiki.repository.add(@path)
      GitWiki.repository.commit_index(msg)
    end
  end

  def tree_link
    paths = @path.split("/")
    if paths.length == 1
      "<a href='/pages/#{@path[0..-6]}'>#{@path[0..-6]}</a>"
    else
      base = ""
      out  = ""
      paths[0..-2].each do |e|
        out << " <a href='/pages/#{base}#{e}/'>#{e}</a> /"
        base << "#{e}/"
      end
      out <<  " #{paths[-1][0..-6]}"
      return out
    end
  end
end

get '/' do
  redirect "/pages/"
  #@page = Page.find_or_create(GitWiki.root_page)
  #haml :show
end

get '/pages/' do
  @pages = Page.find_all
  haml :list
end

get %r{/pages/(.*)} do |page|
  case page
  when %r{(.*)/edit$}
    @page = Page.find_or_create($1)
    haml :edit
  when %r{(.*/)$}
    @pages = Page.find_all($1)
    haml :list
  else
    @page = Page.find_or_create(page)
    haml :show
  end
end

post %r{/pages/(.+)/edit} do |page|
  @page = Page.find_or_create(page)
  @page.save!(params[:content], params[:msg])
  redirect @page.url, 303
end


configure do
  GitWiki.wiki_path = ARGV[0] || Dir.pwd
  GitWiki.root_page = 'index'
  GitWiki.extension = '.text'
  GitWiki.link_pattern = /\[\[(.*?)\]\]/
end
