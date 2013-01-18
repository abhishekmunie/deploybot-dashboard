http        = require 'http'
https       = require 'https'
crypto      = require 'crypto'
heroku      = require 'heroku'
express     = require 'express'
fs          = require 'fs'
url         = require 'url'
path        = require 'path'
zlib        = require 'zlib'
StreamCache = require 'StreamCache'
pg          = require 'pg'
PGStore     = require 'connect-pg'

console.log "Dependencies loaded."

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
  wwwgz[i] = new StreamCache()
  fs.createReadStream(path.join(process.cwd(), url.parse("/www#{i}").pathname)).pipe(zlib.createGzip()).pipe(wwwgz[i])

C404 = new StreamCache()
fs.createReadStream(path.join(process.cwd(), url.parse("/www/404.html").pathname)).pipe(zlib.createGzip()).pipe(C404)

pgConnect = (callback) ->
  console.log "Connecting to postgres... on #{process.env.DATABASE_URL} || #{process.env.HEROKU_POSTGRESQL_OLIVE_URL}"
  pg.connect process.env.DATABASE_URL || process.env.HEROKU_POSTGRESQL_OLIVE_URL, (err, client) ->
    console.error JSON.stringify(err) if err
    console.log "Connected."
    client.query 'CREATE SCHEMA  web' .on 'end', () ->

    callback(client) if client

app.configure () ->
  console.log "Configuring App..."
  app.use express.favicon()
  app.use express.cookieParser()
  app.use express.session
    store: new PGStore(pgConnect),
    secret: process.env.SESSION_SECRET

authUser = (req, res, next) ->
  if req.session.secure_state
      next()
  else
    res.send 401, { error: 'Unauthorized!' }

options_AccessToken =
  hostname: 'github.com',
  port: 443,
  path: '/login/oauth/access_token',
  headers:
    'Accept': 'application/json'
  method: 'POST'

app.get '/token/github?code=:code', authUser, (req, res) ->
  req = https.request options, (res) ->
    console.log "statusCode: ", res.statusCode
    console.log "headers: ", res.headers

    res.on 'data', (d) ->
      req.session.access_token = JSON.parse(d)["access_token"]
      https.get "https://api.github.com/user?access_token=#{req.session.access_token}", (res) ->
        console.log("statusCode: ", res.statusCode);
        console.log("headers: ", res.headers);

        res.on 'data', (d) ->
          res.status 200
          res.type 'application/json'
          res.end d

      .on 'error', (e) ->
        console.error e

  req.end("client_id=#{process.env.GitHub_ID}&client_secret=#{process.env.GitHub_Secret}&code=#{req.params.code}&state=#{req.session.state}")

  req.on 'error', (e) ->
    console.error e
    return e

app.get '*', (req, res) ->
  unless req.session.secure_state
    req.session.secure_state = crypto.randomBytes(256)
    res.cookie 'secure_state', req.session.secure_state,
      domain: '.example.com'
      path: '/admin'
      #secure: true
  uri = req.url

  if cache = (wwwgz[uri] || wwwgz[uri+"index.html"] || wwwgz[uri+"index.htm"])
    res.status 200
    res.type path.extname(uri).split(".")[1] || "html"
    res.set
      'content-encoding'            : 'gzip',
      'Transfer-Encoding'           : 'chunked',
      'Vary'                        : 'Accept-Encoding',
      'X-UA-Compatible'             : 'IE=Edge,chrome=1',
      'Connection'                  : 'Keep-Alive',
      'Access-Control-Allow-Origin' : "#{req.protocol}://#{req.host}"
  else
    cache = C404;
    res.status 404
    res.type "text/plain"
    res.set
      'content-encoding'            : 'gzip',
      'Transfer-Encoding'           : 'chunked',
      'Vary'                        : 'Accept-Encoding',
      'X-UA-Compatible'             : 'IE=Edge,chrome=1',
      'Access-Control-Allow-Origin' : "#{req.protocol}://#{req.host}"

  try
    cache.pipe(res);
  catch e
    res.status 500
    res.end("Request: #{req.url}\nOops! node toppled while getting: #{uri}")

getSource = (heroku_app, callback) ->
  getConfig = heroku.api(process.env.HEROKU_API_KEY, "application/json").request("GET", "/apps/" + heroku_app + "/config_vars")

  getConfig.on "success", (data, response) ->
    config_vars = data
    try
      config_vars = JSON.parse config_vars
    catch err
      console.error "JSON prase error: " + err
      res.end "JSON prase error: " + err

    callback
      repo: config_vars["SOURCE_REPO"],
      branch: (config_vars["SOURCE_BRANCH"]||"master")

  getConfig.on "error", (data, response) ->
    console.error "ERROR: #{heroku_app} => #{error_msg[response.statusCode] || "Some error occured."}"
    callback
      error_res: response
      error_data: data

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
console.log "Listening..."