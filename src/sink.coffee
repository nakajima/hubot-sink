{Adapter, User, TextMessage} = require 'hubot'

WebSocketClient = require('websocket').client

WS_BASE = process.env.SINK_WS_TOKEN || 'ws://sink-ws.herokuapp.com/'

class SinkAPI
  constructor: (robot) ->
    @robot = robot

  poll: =>
    data ?= {}
    data.token = process.env.SINK_API_TOKEN
    base = process.env.SINK_API_URL || 'https://sink-rails.herokuapp.com/'
    @robot.http(base + 'poll').query(data).get()

  get: (path, data) =>
    data ?= {}
    data.token = process.env.SINK_API_TOKEN
    base = process.env.SINK_API_URL || 'https://sink-rails.herokuapp.com/v1/'
    @robot.http(base + path).query(data).get()

  post: (path, data) =>
    data ?= {}
    data.token = process.env.SINK_API_TOKEN
    data = JSON.stringify(data)
    base = process.env.SINK_API_URL || 'https://sink-rails.herokuapp.com/v1/'
    @robot.http(base + path).headers('Content-type': 'application/json').post(data)

  registerWebsocket: (callback) =>
    @post("channels")((err, resp, body) =>
      try
        callback JSON.parse(body).uuid
      catch
        @robot.logger.info "error registering web socket"
        @robot.logger.info body
    )

class Sink extends Adapter
  constructor: ->
    super

    @client = new WebSocketClient
    @sink = new SinkAPI(@robot)

  send: (envelope, strings...) ->
    for string in strings
      @robot.logger.info string
      @sink.post "rooms/#{envelope.user.room_id}/messages", message: { text: string, source_guid: "hubot-#{Number(new Date())}" }

  reply: (envelope, strings...) ->
    strings = strings.map (s) -> "#{envelope.user.username}: #{s}"
    @send envelope, strings...

  run: ->
    @robot.logger.info "Run"
    @client.on 'connect', (connection) =>
      @emit "connected"
      connection.on 'message', (message) =>
        return unless message.type is 'utf8'
        event = JSON.parse(message.utf8Data)
        return unless event.type is "Message"

        message = event.payload
        message.user.room_id = message.room_id
        user = new User(message.user.id, message.user)
        message = new TextMessage(user, message.text, message.id)
        @receive message

    @sink.registerWebsocket (uuid) =>
      @client.connect WS_BASE + uuid
      setInterval =>
        @sink.poll()
      , 10000

exports.use = (robot) ->
  new Sink robot
