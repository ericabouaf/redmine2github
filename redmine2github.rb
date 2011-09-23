require 'rubygems'
require 'rest-client'
require 'json'
require 'date'

#########
# Config
#########

# edit redmine url & basic auth credentials
REDMINE_URL = "https://user:password@redmine.yourdomain.com"

# edit github username, password, and path repository
GITHUB_URL = "https://neyric:****@api.github.com/repos/neyric/redmine2github"

CLOSED_LABELS = ["Fixed", "Rejected", "Won't Fix", "Duplicate", "Obsolete", "Implemented"]

USER_MAPPING = {
  "Eric" => "neyric"
  # , "RedmineUser" => "GitHub user"
}

# end of config


class IssueMigrator
  
  attr_accessor :redmine_issues
  attr_accessor :issue_pairs
  
  attr_accessor :milestones
  attr_accessor :labels
  attr_accessor :issues
  
  def start
    
    self.milestones = {}
    self.labels = {}
    self.issues = {}
    
    # TODO: must loop through all pages !
    
    # Get existing milestones
    puts "Listing milestones..."
    response = RestClient.get GITHUB_URL+"/milestones?per_page=100",:accept => :json
    JSON.parse(response).each { |milestone| 
      self.milestones[milestone["title"]] = milestone
    }
    response = RestClient.get GITHUB_URL+"/milestones?state=closed&per_page=100",:accept => :json
    JSON.parse(response).each { |milestone| 
      self.milestones[milestone["title"]] = milestone
    }
    
    # Get existing labels :
    puts "Listing labels..."
    response = RestClient.get GITHUB_URL+"/labels?per_page=100",:accept => :json
    JSON.parse(response).each { |lab| 
      self.labels[lab["name"]] = lab
    }
    
    # Get existing issues : 
    puts "Listing open issues..."
    response = RestClient.get GITHUB_URL+"/issues?state=open&per_page=100",:accept => :json
    JSON.parse(response).each { |issue| 
      self.issues[issue["title"]] = issue
    }
    puts "Listing closed issues..."
    response = RestClient.get GITHUB_URL+"/issues?state=closed&per_page=100",:accept => :json
    JSON.parse(response).each { |issue| 
      self.issues[issue["title"]] = issue
    }
    
    # Get issues from Redmine
    puts "Getting redmine issues..."
    get_issues
    
    # Convert issues to GitHub format
    self.issue_pairs = redmine_issues.map { |redmine_issue| 
      github_issue = create_issue(redmine_issue)
      #migrate_comments(github_issue, redmine_issue)
      [github_issue, redmine_issue]
    }
    
    save_issues
    
  end
  
  
  
  # Get Issues from Redmine
  def get_issues
    
    offset = 0
    issues = []
    begin
      json = RestClient.get(REDMINE_URL+"/issues", {:params => {:format => :json, :status_id => '*', :limit => 100, :offset => offset}})
      result = JSON.parse(json)
      issues << [*result["issues"]]
      offset = offset + result['limit']
      print '.'
    end while offset < result['total_count']
    puts

    puts "Retreived redmine issue index."
    issues.flatten!

    #puts "Getting comments"
    #issues.map! do |issue|
    #  get_comments(issue)
    #end
    #puts "Retreived comments."

    self.redmine_issues = issues.reverse!
  end


  def create_issue redmine_issue
    
    body = <<BODY

Created by: **#{redmine_issue["author"]["name"]}**
On #{DateTime.parse(redmine_issue["created_on"]).asctime}

*Priority: #{redmine_issue["priority"]["name"]}*
*Status: #{redmine_issue["status"]["name"]}*

#{redmine_issue["description"]}
BODY
    
    params = { 
      "title" => redmine_issue["subject"],
      "body" => body
    }

    if redmine_issue["fixed_version"]
      params["milestone"] = redmine_issue["fixed_version"]["name"]
    end

    if !self.milestones[params["milestone"]]
      self.milestones[params["milestone"]] = nil
    end
    
    if assignee = redmine_issue["assigned_to"]
      if USER_MAPPING[assignee["name"]] == nil
        puts "UNKNOWN USER_MAPPING : "+assignee["name"]
      end
      params["assignee"] = USER_MAPPING[assignee["name"]]
    end
    
    labels = []
    
    if priority = redmine_issue["priority"]
      labels << priority["name"]
    end
    
    ["tracker", "status", "category"].each do |thing|
      next unless redmine_issue[thing]
      value = redmine_issue[thing]["name"]
      labels << value  unless ["Nouveau"].include?(value)
    end
    
    
    labels.each { |lab|
      self.labels[lab] = nil if !self.labels[lab]
    }
    
    params["state"] = "closed" if CLOSED_LABELS.include?(redmine_issue["status"]["name"])
    
    params["labels"] = labels
    params
  end

  
  def create_milestone(name)
    puts "CREATING MILESTONE #{name}"
    begin
      r = RestClient.post GITHUB_URL+"/milestones", { 'title' => name }.to_json, :content_type => :json, :accept => :json
      
      result = JSON.parse(r)
      
    rescue RestClient::ExceptionWithResponse => e
      response = JSON.parse(e.http_body)
      puts response.inspect
      
      if response["errors"].first["code"] == "already_exists"
        puts "ALREADY EXISTS ??"
      end
      
    end
    
    result
  end
  
  def create_label(name)
    
      puts "CREATING LABEL #{name}"
    begin
      r = RestClient.post GITHUB_URL+"/labels", { 'name' => name, 'color' => 'CCCCCC' }.to_json, :content_type => :json, :accept => :json
      
      result = JSON.parse(r)
      
    rescue RestClient::ExceptionWithResponse => e
      response = JSON.parse(e.http_body)
      puts response.inspect
      
      if response["errors"].first["code"] == "already_exists"
        puts "ALREADY EXISTS ??"
      end
      
    end
    
    result
  end

  # def migrate_comments github_issue, redmine_issue
  #     redmine_issue["journals"].each do |j|
  #       next if j["notes"].nil? || j["notes"] == ''
  #       github_issue.comment <<COMMENT
  # Comment by: **#{j["user"]["name"]}**
  # On #{DateTime.parse(j["created_on"]).asctime}
  # 
  # #{j["notes"]}
  # COMMENT
  #     end
  #   end
  # 
  #   def get_comments redmine_issue
  #     print "."
  #     issue_json = JSON.parse(RestClient.get(REDMINE_URL+"/issues/#{redmine_issue["id"]}", :params => {:format => :json, :include => :journals}))
  #     issue_json["issue"]
  #   end

  def save_issues
    
    # Save milestones
    self.milestones.keys.each { |milestone|
      if self.milestones[milestone]
        puts "Milestone '#{milestone}' already exists"
      else
        self.milestones[milestone] = create_milestone(milestone)
      end
    }
    
    # Save labels
    self.labels.keys.each { |lab|
      if self.labels[lab]
        puts "Label '#{lab}' already exists"
      else
        self.labels[lab] = create_label(lab)
      end
    }
    
    puts self.milestones.to_json
    puts self.labels.to_json
    
    i = 0
    s=issue_pairs.size
    
    issue_pairs.each do |pair|
      
      i += 1
      
      github_issue = pair[0]
      redmine_issue = pair[1]
    
      puts "========================="
      #puts redmine_issue.to_json
      
      if github_issue["milestone"] and self.milestones[github_issue["milestone"]]
        puts "ticket milestone  "+github_issue["milestone"]
        milestoneId = self.milestones[github_issue["milestone"]]["url"].split('/').last.to_i
        github_issue["milestone"] = milestoneId
      end
      
      #puts github_issue.to_json
        
      begin
        
        if self.issues[ github_issue["title"] ]
        
          puts "ISSUE ALREADY EXISTS"
          #issueId = 
        
        else
        
          response = RestClient.post GITHUB_URL+"/issues", github_issue.to_json, :content_type => :json, :accept => :json
          
          puts "x_ratelimit_remaining : "+response.headers[:x_ratelimit_remaining]
          puts "Prog : #{i}/#{s}"
          
          issueId = response.headers[:location].split('/').last
          
          if github_issue["state"] == "closed"
            puts "CLOSE ISSUE !"
            RestClient.patch GITHUB_URL+"/issues/"+issueId, {:state => "closed"}.to_json, :content_type => :json, :accept => :json
          end
        
        end
        
      rescue RestClient::ExceptionWithResponse => e
        response = JSON.parse(e.http_body)
        puts response.inspect

      end
        
        
    end
    
  end
  
end

m = IssueMigrator.new
m.start