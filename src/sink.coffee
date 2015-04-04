{Adapter, User, TextMessage} = require 'hubot'

WebSocketClient = require('websocket').client
request = require('request')

WS_BASE = process.env.SINK_WS_TOKEN || 'ws://sink-ws.herokuapp.com/'
SINK_API_BASE = process.env.SINK_API_URL || 'https://sink-rails.herokuapp.com/v1/'

WEBSOCKET_ID_COUNTER = 0

class SinkAPI
  constructor: (robot) ->
    @robot = robot

  get: (path, data) =>
    data ?= {}
    data.token = process.env.SINK_API_TOKEN
    url = SINK_API_BASE + path
    request url: url, method: 'GET', qs: data

  post: (path, data, callback) =>
    url = SINK_API_BASE + path + "?token=#{process.env.SINK_API_TOKEN}"
    headers = { 'Content-type': 'application/json' }
    options = url: url, headers: headers, method: 'POST', body: JSON.stringify(data)
    request options, callback

  registerWebsocket: (callback) =>
    @post "channels", {}, (err, resp, body) =>
      try
        callback JSON.parse(body).uuid
      catch
        @robot.logger.info "error registering web socket"
        @robot.logger.info body

class Sink extends Adapter
  constructor: ->
    super
    @sink = new SinkAPI(@robot)
    @_registerWebsocket()

  send: (envelope, strings...) ->
    @robot.logger.info "calling send from client #{@client.__websocketID}"
    @robot.logger.info strings
    for string in strings
      @robot.logger.info string
      @sink.post "rooms/#{envelope.user.room_id}/messages", message: { text: string, source_guid: "hubot-#{Number(new Date())}" }

  reply: (envelope, strings...) ->
    strings = strings.map (s) -> "#{envelope.user.username}: #{s}"
    @send envelope, strings...

  run: ->
    @robot.logger.info "Run"

  _registerWebsocket: =>

    if @interval
      clearInterval(@interval)

    @robot.logger.info "registering websocket"
    @client = new WebSocketClient
    @client.__websocketID = WEBSOCKET_ID_COUNTER++

    @sink.registerWebsocket (uuid) =>
      @client.on 'connect', (connection) =>
        @emit "connected"

        connection.on 'connect', =>
          @robot.logger.info "WEBSOCKET CONNECTED"

        connection.on 'close', (e) =>
          @robot.logger.info "LOST WEBSOCKET CONNECTION."
          @robot.logger.info e
          @sink.post("channels/#{uuid}/destroy")
          @_registerWebsocket()

        connection.on 'message', (message) =>

          return unless message.type is 'utf8'
          event = JSON.parse(message.utf8Data)
          return unless event.type is "Message"

          message = event.payload
          message.user.room_id = message.room_id
          @robot.logger.info "on message from client #{@client.__websocketID}: #{message.text}"
          user = new User(message.user.id, message.user)
          message = new TextMessage(user, message.text, message.id)
          @receive message
      @client.connect WS_BASE + uuid

      @interval = setInterval =>
        @sink.get("poll/#{uuid}")
      , 10000

exports.use = (robot) ->
  new Sink robot
