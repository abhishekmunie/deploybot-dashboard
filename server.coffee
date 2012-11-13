http        = require 'http'
heroku      = require 'heroku'
express     = require 'express'

error_msg =
  "200": "OK - Request succeeded, response contains requested data.",
  "401": "Unauthorized - deploybot is not authorized to access this app.",
  "402": "Payment Required - You must confirm your billing info to use this API.",
  "403": "Forbidden - deploybot's access level don't permit it to assess the requires info.",
  "404": "Not Found - App was not found.",
  "412": "Precondition Failed - This API has been deprecated.",
  "422": "Unprocessable Entity - An error has occurred.",
  "423": "Locked - This API command requires confirmation."

app = express()

app.get '/', (req, res) ->
  res.send 'Comming Soon...\nTo test a Heroku app send request at /test/:app'

app.get "/test/:app", (req, res) ->
  heroku_app = req.params.app
  
  res.setHeader 'Content-Type', 'text/plain'
  res.setHeader 'Content-Length', body.length

  deploy_config = heroku.api(process.env.HEROKU_API_KEY, "application/json").request("GET", "/apps/" + heroku_app + "/config_vars")

  deploy_config.on "success", (data, response) ->
    config_vars = data
    try
      config_vars = JSON.parse config_vars
    catch err
      console.error "JSON prase error: " + err
      res.end "JSON prase error: " + err

    body = "#{heroku_app} will deploy deploy using #{config_vars["GIT_SOURCE_REPO"]} ##{config_vars["GIT_SOURCE_BRANCH"]||"master"}"
    res.status 200
    res.end body
    

  deploy_config.on "error", (data, response) ->
    res.status response.statusCode
    res.end "ERROR: #{heroku_app} => #{error_msg[response.statusCode] || "Some error occured."}"

.listen process.env.C9_PORT || process.env.PORT || process.env.VCAP_APP_PORT || process.env.VMC_APP_PORT || 1337 || 8001