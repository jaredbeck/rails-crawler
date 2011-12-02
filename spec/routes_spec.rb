require File.dirname(__FILE__) + '/../lib/crawler'
 
describe "Crawler" do
  RAILS_PATH = File.dirname(__FILE__) + '/../priv/CarApp'

  before(:each) do
    @crawler = Crawler.new
    @crawler.load_app RAILS_PATH
    Car.delete_all
    @crawler.process "/index.html"
  end
  
  it "have a result for the root URL" do
    matched = false
    
    matches = @crawler.results.each do |m|
      matched = true if m[:url] == "/index.html" and m[:method] == :get
    end
    
    matched.should == true        
  end

  it "should get the response code for each path" do
    @crawler.results.each do |r|
      r[:status].should_not == nil
    end    
  end
  
  it "should have the correct response code" do
    found = 0

    @crawler.results.each do |r|
      if r[:url] == '/deadlink'
        r[:status].should == 404
        found += 1
      elsif r[:url] == '/cars' and r[:method].to_s == 'get'
        r[:status].should == 200
        found += 1
      end
    end
    
    found.should == 2
  end      
  
  it "should crawl image tags" do
    results = @crawler.results.map do |m|
      true if m[:url] == "/images/rails.png" and m[:method] == :get
    end

    results.compact.should_not be(:empty)
  end
  
  it "should crawl link tags" do
    results = @crawler.results.map do |m|
      true if m[:url] == "/stylesheets/scaffold.css" and m[:method] == :get
    end

    results.compact.should_not be(:empty)
  end    
  
  it "should crawl pages reachable via links" do
    results = @crawler.results.map do |m|
      true if m[:url] == "/cars" and m[:method] == :get
    end

    results.compact.should_not be(:empty)
  end
  
  it "should crawl pages reachable via forms" do
    results = @crawler.results.map do |m|
      true if m[:url] == "/cars/new" and m[:method] == :post
    end
    
    results.compact.should_not be(:empty)
  end
  
  describe "routes" do
    it "should have a list of routes" do
      @crawler.routes.should_not be(:nil)      
    end
    
    it "should have a list of dead pages" do
      @crawler.routes[:not_found].should have_at_least(1).items
    end
    
    it "should discover unused routes" do
      matched = false
      @crawler.routes.each_pair do |route,request_array|
        if route.to_s =~ /cars/ and route.to_s =~ /show/
          matched = true
          request_array.should be_empty
        end          
      end
      
      matched.should == true      
    end
  end
end