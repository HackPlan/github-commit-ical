express = require 'express'
request = require 'request'
async = require 'async'
harp = require 'harp'
path = require 'path'
ical = require 'ical-generator'
_ = require 'underscore'

default_request_flags =
  headers:
    'User-Agent': 'github-commit-ical'

app = express()

app.use harp.mount(path.join(__dirname, 'static'))

app.get '/:username', (req, res) ->
  username = req.param 'username'

  request "https://api.github.com/users/#{username}/events", default_request_flags, (err, _res, body) ->
    events = _.filter JSON.parse(body), (event) ->
      return event.type == 'PushEvent'

    async.map events, (event, callback) ->
      async.map event.payload.commits, (commit, callback) ->
        request "https://api.github.com/repos/#{event.repo.name}/git/commits/#{commit.sha}", default_request_flags, (err, _res, body) ->
          real_time = JSON.parse(body).committer.date

          callback err,
            start: new Date real_time
            end: new Date real_time
            summary: "#{commit.message} (#{event.repo.name})"
            url: commit.html_url

      , (err, result) ->
        callback err, result

    , (err, result) ->
      cal = ical()
      cal.setDomain('commit-calendar.newsbee.io').setName("#{username} Commit History")

      for commits in result
        for commit in commits
          cal.addEvent commit

      res.header 'Content-Type', 'text/calendar; charset=utf-8'
      res.status(200).end(cal.toString())

app.listen 3000
