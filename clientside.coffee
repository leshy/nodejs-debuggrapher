bootstrap = require 'bootstrap-browserify'
comm = require 'comm/clientside'
Backbone = require 'backbone4000'
helpers = require 'helpers'

_ = require 'underscore'
$ = require 'jquery-browserify'
async = require 'async'
flot = require 'flot'

settings = { websockethost: "http://" + window.location.host, simulatedelay: true }

env = {}

window.env = env
env.settings = settings

logger = comm.MsgNode.extend4000
    log: (text,data,tags...) ->
        tagshash = {}
        _.map tags, (tag) -> tagshash[tag] = true
        @msg({tags: tagshash, text: text, data: data, time: new Date().getTime()})

consoleLogger = consoleLogger = logger.extend4000
    initialize: ->
        @subscribe true, (msg,reply,next,transmit) ->
            text = msg.text
            #if msg.tags.error then text = text.red
            if msg.tags.error and _.keys(msg.data).length then json = " " + JSON.stringify(msg.data) else json = ""
            console.log  _.keys(msg.tags).join(', ') + " " + text + json
            reply.end(); next(); transmit();

initLogger = (env,callback) ->
    env.logger = new logger()
    env.consoleLogger = new consoleLogger()
    env.logger.pass()
    env.logger.connect(env.consoleLogger)
    env.log = env.logger.log.bind(env.logger)

    env.logres = (name, callback) ->
        (err,data) -> 
            if (err)
                env.log name, {error: err}, 'init', 'fail'
            else
                env.log name, {}, 'init', 'ok'
            callback(err,data)
        
    env.log('logger', {}, 'init', 'ok')
    callback()

gatherInfo = (env,callback) ->
    env.hostdata = {}    
    #if navigator.doNotTrack then callback(); return
    crawl = (object,attributes) -> helpers.hashmap attributes, (value,attr) -> object[attr]

    env.hostdata.browser = crawl navigator, ['appCodeName', 'appVersion', 'userAgent', 'vendor']
    env.hostdata.screen = crawl window.screen, ['height','width','colorDepth']
    env.hostdata.os = platform: navigator.platform, language: navigator.language
    callback()
    
initWebsocket = (env,callback) ->
    env.websocket = websocket = new comm.WebsocketClient realm: 'web'
    #websocket.pass()
#    websocket.subscribe true, (msg,reply,next,transmit) ->
#        console.log('>>>',msg.render()); reply.end(); next()
    callback()
    
websocketConnect = (env,callback) ->
    doconnect = ->
        env.websocket.connect env.settings.websockethost, ->
            callback()
    if window.location.hostname isnt 'localhost' or env.settings.simulatedelay isnt true then doconnect() else setTimeout(doconnect, 400)

initdict =
    logger: (callback) -> initLogger env,callback
    gatherinfo: [ 'logger', (callback) -> gatherInfo env, env.logres('host info', callback) ]
    websocket: [ 'logger', (callback) -> initWebsocket env, env.logres('initializing websocket', callback) ]
    websocketconnect: [ 'websocket', (callback) -> websocketConnect env, env.logres('connecting websocket',callback) ]
    streamreader: [ 'streamReader', (callback) -> initStreamReader env, env.logres('initializing stream reader',callback) ]

init = (env,callback) ->
    async.series [
        initdict.logger,
        _.last(initdict.gatherinfo),
        _.last(initdict.websocket),
        _.last(initdict.websocketconnect),
        _.last(initdict.streamreader) ],
        callback

init env, (err,data) ->
    if err then env.log('clientside init failed', {}, 'init', 'fail', 'error');return
    env.log('clientside ready', {}, 'init', 'ok', 'completed')

randomWalk = (data,len=300) ->
    if not data?.length then data = [ 50 ]
    last = _.last(data)
#    data.push last + helpers.randrange(10) - 5 + ((50 - last) / 30)
    data.push last + helpers.randrange(10) - 5
    if data.length > len
        data.shift()
        return data

    else return randomWalk data, len

cook = (data) ->
    max = _.reduce data, (r,x) ->
        if not r then r = 0
        if x > r then return x else return r
    {
        lines: { show: true, fill: true }
        points: { show: false }
        data: data = _.map data, (n,i) -> [i,n / max]
    }

initStreamReader = (env,callback) ->
    class DataStream
        constructor: (init) ->
            @maxlen = init.maxlen or 200
            @name = init.name or throw 'no name?'
            @data = init.data or [ 0 ]
            
            graphwindow = $("<div class='window'></div>")
            graphwindow.append $("<div class='graphtitle'>#{@name}</div>")
            graphwindow.append @div = $("<div class='graphcontainer'></div>")
            $(document.body).append graphwindow
            
            @plot = $.plot @div, [ cook(@data) ], { series: { shadowSize: 0 }, yaxis: { show: false, min: 0, max: 1 }, xaxis: { show: false, min: 0, max: @maxlen } }
            
            env.websocket.subscribe { stream: @name }, (msg,reply) => reply.end(); @push msg.value

        redraw: ->
            @plot.setData([cook(@data)])
            @plot.draw()
            
        push: (value) -> 
            @data.push(value)
            if @data.length > (@maxlen + 1) then @data.shift()
            @redraw()

    streams = {}
    
    env.websocket.subscribe { stream: true, value: true }, (msg,reply,next,transmit) ->
        if not streams[msg.stream] then streams[msg.stream] = new DataStream name: msg.stream, data: [ msg.value ]
        next()
        
    callback()

    