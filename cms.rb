require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

configure do
  enable :sessions
  set :session_secret, 'secret'
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)

  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  end
end

def load_user_credentials
  credentials_path =
    if ENV["RACK_ENV"] == 'test'
      File.expand_path("../test/users.yml", __FILE__)
    else
      File.expand_path("../users.yml", __FILE__)
    end
  YAML.load_file(credentials_path)
end

def valid_credentials?(username, password)
  credentials = load_user_credentials
  return false unless credentials.key?(username)

  bcrypt_password = BCrypt::Password.new(credentials[username])
  bcrypt_password == password
end

def user_signed_in?
  session.key?(:username)
end

def redirect_unless_signed_in
  unless user_signed_in?
    session[:message] = 'You must be signed in to do that.'
    redirect '/'
  end
end

get "/" do
  pattern = File.join(data_path, '*')
  @files = Dir.glob(pattern).map { |path| File.basename(path) }
  erb :index
end

get "/users/signin" do
  erb :signin
end

post "/users/signin" do
  username = params[:username]
  password = params[:password]

  if valid_credentials?(username, password)
    session[:username] = username
    session[:message] = "Welcome!"
    redirect '/'
  else
    session[:message] = 'Invalid credentials.'
    status 422
    erb :signin
  end
end

post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

get "/new" do
  redirect_unless_signed_in
  erb :new
end

post "/create" do
  redirect_unless_signed_in
  filename = params[:filename].to_s

  if filename.strip == ''
    session[:message] = "A name is required."
    status 422
    erb :new
  elsif !['.txt', '.md'].include?(File.extname(filename))
    session[:message] = "The file extension must be .txt or .md."
    status 422
    erb :new
  else
    file_path = File.join(data_path, filename)
    File.write(file_path, "")
    session[:message] = "#{filename} has been created."
    redirect '/'
  end
end

get "/:filename" do
  filename = params[:filename]
  file_path = File.join(data_path, filename)

  if File.exist?(file_path)
    @content = load_file_content(file_path)
  else
    session[:message] = "#{filename} does not exist."
    redirect '/'
  end
end

get "/:filename/edit" do
  redirect_unless_signed_in

  @filename = params[:filename]
  file_path = File.join(data_path, @filename)
  @content = File.read(file_path)
  erb :edit_file
end

post "/:filename" do
  redirect_unless_signed_in

  filename = params[:filename]
  file_path = File.join(data_path, filename)

  File.write(file_path, params[:content])

  session[:message] = "#{filename} has been updated."
  redirect '/'
end

post '/:filename/delete' do
  redirect_unless_signed_in

  filename = params[:filename]
  file_path = File.join(data_path, filename)
  File.delete(file_path)
  session[:message] = "#{filename} has been deleted."
  redirect '/'
end
