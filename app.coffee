express = require 'express'
request = require 'request'
async = require 'async'
harp = require 'harp'
path = require 'path'
ical = require 'ical-generator'
redis = require 'redis'
_ = require 'underscore'

config = require './config'

redis_client = redis.createClient()

sendRequest = (path, callback) ->
  {user, pass} = config.auth
  url = "https://#{user}:#{pass}@api.github.com#{path}"

  request url,
    headers:
      'User-Agent': 'github-commit-ical'
  , callback

app = express()

app.use harp.mount(path.join(__dirname, 'static'))

app.get '/:username', (req, res) ->
  username = req.param 'username'

  sendRequest "/users/#{username}/events?per_page=300", (err, _res, body) ->
    body = JSON.parse body

    unless _.isArray body
      return res.status(404).end()

    events = _.filter body, (event) ->
      return event.type == 'PushEvent'

    async.map events, (event, callback) ->
      async.map event.payload.commits, (commit, callback) ->
        redis_client.get "github-commit-ical:#{commit.sha}", (err, result) ->
          if result
            result = JSON.parse result

            result.start = new Date result.start
            result.end = new Date result.end

            callback err, result

          else
            sendRequest "/repos/#{event.repo.name}/git/commits/#{commit.sha}", (err, _res, body) ->
              body = JSON.parse body

              if body.committer
                result =
                  start: new Date body.committer.date
                  end: new Date body.committer.date
                  summary: "#{commit.message} (#{event.repo.name})"
                  url: body.html_url
              else
                result = {}

              redis_client.set "github-commit-ical:#{commit.sha}", JSON.stringify(result), ->
                callback err, result

      , (err, result) ->
        callback err, result

    , (err, result) ->
      cal = ical()
      cal.setDomain('commitcal.newsbee.io').setName("#{username} Commit History")

      for commits in result
        for commit in commits
          if commit.summary
            cal.addEvent commit

      console.log "[Request by] #{username}"
      console.log "[X-RateLimit-Remaining] #{_res.headers['x-ratelimit-remaining']}"

      res.header 'Content-Type', 'text/calendar; charset=utf-8'
      res.status(200).end(cal.toString())

app.listen 3000
