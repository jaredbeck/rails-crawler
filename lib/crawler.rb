
require 'rubygems'
require 'action_controller'
require 'hpricot'

# In Rails 3, Integration/Runner has moved to ActionDispatch
require 'action_dispatch'

class Crawler
  include ActionDispatch::Integration::Runner

  attr_reader :routes, :results, :path
  attr_internal :open

  # In Rails 2, it was not necessary to override Runner.app() like this,
  # which may indicate that we are using the new ActionDispatch API incorrectly
  def app
    Rails.application
  end

  def load_app(path)
    require path + '/config/boot'
    require path + '/config/environment'
    require path + '/config/routes'

    @path = path

    # `@routes` is a hash which maps each route object to an (initially
    # empty) array of request hashes.  After crawling is complete, this
    # hash can be queried to determine, for example, how many times a
    # given route was requested.
    @routes = { :static => [], :not_found => [] }
    Rails.application.routes.routes.each do |r|
      @routes[r] = [] unless r.nil?
    end
  end

  def process(url)
    @results = []
    @open = [{:method => :get, :url => url}]

    until @open.empty?
      step
    end
  end

  protected

  def step
    request = @open.pop
    result, outgoing = process_request request
    @results.push result
    outgoing.each do |x|
      @open.push(x) unless already_processed? x
    end
  end

  def already_processed?(request)
    not (@open + @results).map { |x|
              if x[:url] == request[:url] and
                 x[:method] == request[:method]
                return true
              end
            }.compact.empty?
  end

  def static_path(url)
    if url == "/"
      "#{@path}/public/index.html"
    else
      "#{@path}/public/#{url}"
    end
  end

  def is_static_file?(url)
    File.exist? static_path(url)
  end

  def process_request(request)

    # Invoke the appropriate request method (eg. get, post)
    method(request[:method]).call request[:url]

    request[:route] = find_route request[:url], request[:method]

    if request[:route] == :static
      request[:status] = 200
    else
      request[:status] = status
    end

    # Extract outgoing links
    if request[:route] == :static
      f = File.new static_path(request[:url])
      body = f.read
      f.close
      outgoing_links = extract_outgoing_links(body)
    elsif [200, 302].include? request[:status]
      outgoing_links = extract_outgoing_links(response.body)
    else
      outgoing_links = []
    end

    # Record the request.  See comment above explaining `@routes`
    routes[request[:route]].push request

    return request, outgoing_links
  end

  # `find_route` returns :static, :not_found, or the first route object that matches
  # Essentially, it returns one of the keys of `@routes`
  def find_route(url, method)
    return :static if is_static_file?(url)

    # Ask Rails which route, if any, matches `url` and `method`.  recognize_path()
    # returns a hash, eg. `{:action=>"index", :controller=>"cars"}`
    begin
      route_params = Rails.application.routes.recognize_path(url, { :method => method })
    rescue ActionController::RoutingError
      return :not_found
    end

    # Find the first Route object that matches the `route_params` hash returned by
    # recognize_path() above.  Naturally, we skip the two "placeholders" which are
    # not actually Route objects.
    matching_routes = @routes.keys.select do |r|
      next if [:static, :not_found].include? r

      (r.requirements[:action] == route_params[:action] \
        and r.requirements[:controller] == route_params[:controller])
    end
    return matching_routes.first
  end

  def extract_outgoing_links(body)
    anchors = Hpricot(body).search("//a").map do |a|
      attrs = a.attributes.to_hash
      anchor_method = attrs.has_key?('data-method') ? attrs['data-method'] : 'get'
      {:url => a[:href], :method => anchor_method.to_sym}
    end

    images = Hpricot(body).search("//img").map do |a|
      {:url => a[:src], :method => :get}
    end

    links = Hpricot(body).search("//link").map do |a|
      {:url => a[:href], :method => :get}
    end

    buttons = Hpricot(body).search("//form").map do |f|
      {:url => f[:action], :method => f[:method].to_sym}
    end

    anchors + images + links + buttons
  end
end
