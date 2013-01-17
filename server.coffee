http        = require 'http'
heroku      = require './lib/heroku'
express     = require 'express'
fs          = require 'fs'
url         = require 'url'
path        = require 'path'
zlib        = require 'zlib'
StreamCache = require './lib/StreamCache'

error_msg =
  "200": "OK - Request succeeded, response contains requested data.",
  "401": "Unauthorized - deploybot is not authorized.",
  "402": "Payment Required - You must confirm your billing info to use this API.",
  "403": "Forbidden - deploybot's access level don't permit it to assess the required info. Add bot@abhishekmunie.com as a collaborator.",
  "404": "Not Found - App was not found.",
  "412": "Precondition Failed - This API has been deprecated.",
  "422": "Unprocessable Entity - An error has occurred.",
  "423": "Locked - This API command requires confirmation."

app = express()

wwwFiles = [
  '/index.html',
  '/auth/github/index.html',
  '/auth/heroku/index.html',
  '/main.css',
  '/humans.txt',
  '/robots.txt'
]

wwwgz = {}

for i in wwwFiles
  console.log i
  wwwgz[i] = new StreamCache()
  fs.createReadStream(path.join(process.cwd(), url.parse("/www#{i}").pathname)).pipe(zlib.createGzip()).pipe(wwwgz[i])

C404 = new StreamCache()
fs.createReadStream(path.join(process.cwd(), url.parse("/www/404.html").pathname)).pipe(zlib.createGzip()).pipe(C404)

app.get '*', (req, res) ->
  uri = req.url
  console.log "got #{uri}"

  if cache = (wwwgz[uri] || wwwgz[uri+"index.html"] || wwwgz[uri+"index.htm"])
    console.log 202
    res.status 200
    res.type path.extname(uri).split(".")[1] || "html"
    res.set {
      'content-encoding': 'gzip'
    }
  else
    console.log 404
    cache = C404;
    res.status 404
    res.type "text/plain"
    res.set {
      'content-encoding': 'gzip'
    }
  console.log "hi"

  try
    cache.pipe(res);
  catch e
    res.status 500
    res.end("Request: #{req.url}\nOops! node toppled while getting: #{uri}")

app.post "/test/:app", (req, res) ->
  heroku_app = req.params.app

  deploy_config = heroku.api(process.env.HEROKU_API_KEY, "application/json").request("GET", "/apps/" + heroku_app + "/config_vars")

  deploy_config.on "success", (data, response) ->
    config_vars = data
    try
      config_vars = JSON.parse config_vars
    catch err
      console.error "JSON prase error: " + err
      res.end "JSON prase error: " + err

    body = "#{heroku_app} will deploy deploy using #{config_vars["SOURCE_REPO"]} ##{config_vars["SOURCE_BRANCH"]||"master"}"
    res.status 200
    res.setHeader 'Content-Length', body.length
    res.setHeader 'Content-Type', 'text/plain'
    res.end body

  deploy_config.on "error", (data, response) ->
    res.status response.statusCode
    res.end "ERROR: #{heroku_app} => #{error_msg[response.statusCode] || "Some error occured."}"
###
app.use (err, req, res, next) ->
  if req.xhr
    res.send 500, { error: 'Something blew up!' }
  else
    next err

app.use (err, req, res, next) ->
  res.status 500
  res.render 'error', { error: err }###

app.listen process.env.C9_PORT || process.env.PORT || process.env.VCAP_APP_PORT || process.env.VMC_APP_PORT || 1337 || 8001