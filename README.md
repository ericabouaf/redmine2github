# Redmine2Github

Convert Redmine issues to GitHub issues using API v3 (basic auth)

Adapted from https://github.com/diaspora/redmine-issues to use API v3 (for milestone support)

WARNING: still has some bugs... try to launch it twice...

## Usage

 * edit the _CONFIG_ section in redmine2github.rb
 * launch

    ruby redmine2github.com

## Features

 * labels
 * milestone
 * assignee
 * closed

Does NOT support comments...

## Dependencies

    gem install rest-client
    gem install json


