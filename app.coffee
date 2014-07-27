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

  sendRequest "/users/#{username}/events", (err, _res, body) ->
    events = _.filter JSON.parse(body), (event) ->
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
              unless JSON.parse(body).committer.date
                console.log JSON.parse(body)

              real_time = JSON.parse(body).committer.date

              result =
                start: new Date real_time
                end: new Date real_time
                summary: "#{commit.message} (#{event.repo.name})"
                url: commit.html_url

              redis_client.set "github-commit-ical:#{commit.sha}", JSON.stringify(result), ->
                callback err, result

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
