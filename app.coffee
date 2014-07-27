express = require 'express'
request = require 'request'
harp = require 'harp'
path = require 'path'
ical = require 'ical-generator'

app = express()

app.use harp.mount(path.join(__dirname, 'static'))

app.get '/:username', (req, res) ->
  username = req.param 'username'

  request "https://api.github.com/users/#{username}/events",
    headers:
      'User-Agent': 'github-commit-ical'
  , (err, _res, body) ->
    body = JSON.parse body

    cal = ical()
    cal.setDomain('commit-calendar.newsbee.io').setName("#{username} Commit History")

    for item in body
      if item.type == 'PushEvent'
        for commit in item.payload.commits
          cal.addEvent
            start: new Date item.created_at
            end: new Date item.created_at
            summary: "#{commit.message} (#{item.repo.name})"
            url: commit.url

    res.header 'Content-Type', 'text/calendar; charset=utf-8'
    res.status(200).end(cal.toString())

app.listen 3000
