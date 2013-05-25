bootstrap = require 'bootstrap-browserify'
comm = require 'comm/clientside'
backbone = require 'backbone4000'
helpers = require 'helpers'

_ = require 'underscore'
$ = require 'jquery-browserify'
async = require 'async'
flot = require 'flot'

validator = require 'validator-extras'; v = validator.v

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
    #websocket.subscribe true, (msg,reply,next,transmit) -> console.log('>>>',msg.render()); reply.end(); next()
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
    async.series {
        logger: (callback) -> initLogger env,callback
        gatherinfo: (callback) -> gatherInfo env, env.logres('host info', callback)
        websocket: (callback) -> initWebsocket env, env.logres('initializing websocket', callback)
        websocketconnect: (callback) -> websocketConnect env, env.logres('connecting websocket',callback)
        streamreader: (callback) -> initStreamReader env, env.logres('initializing stream reader',callback)
        }, callback

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
    {
        lines: { show: true, fill: true }
        points: { show: false }
        data: data = _.map data, (n,i) -> [i,n]
    }

getmax = (data) -> _.reduce data, (r, x) -> if x > r then x else r

initStreamReader = (env,callback) ->

    viewModel = backbone.Model.extend4000
        associate: (attribute,div) ->
            updatediv = (value) -> div.html value
            updatediv @get attribute
            @on 'change:' + attribute, updatediv
            
    DataSource = comm.MsgNode.extend4000
        defauls: { maxlen: 100 }
        
        initialize: ->
            @set max: 0
            
            console.log 'created new source', @get 'name'
            @subscribe {source: @get 'name' }, (msg,reply) =>
                #console.log msg
                reply.end()
                if msg.push then @push msg.push
                if msg.change then @change msg.change
                    
            @data = []

        max: -> getmax(@data)

        push: (value) ->
            @data.push(value)
            if @data.length > 100 then shift = @data.shift()

            max = @get 'max'
            if value > max then @set max: value
            else if shift is max then @set max: @max()
            
        change: (value) ->
            #console.log "change", @get('name'), value
            if not @data.length then @data.push 0
            @push _.last(@data) + value
            
        clear: (callback) -> callback()
        
        remoteset: (attribute, value, callback) -> callback()
            
        exportdata: ->
            {
                label: @get 'name'
                lines:
                    show: true
                    fill: true
                points:
                    show: false
                data: _.map @data, (n,i) -> [i,n]
            }
        
    Graph = comm.MsgNode.extend4000
        defaults:
            max: 1
        
        initialize: ->
            @sources = {}
            
            graphwindow = $("<div class='window'></div>")
            graphwindow.append namediv = $("<div class='graphtitle'>#{@get 'name'}</div>")
            graphwindow.append @graphdiv = $("<div class='graphcontainer'></div>")
            $(document.body).append graphwindow

            #@associate 'name', namediv

            @hardredraw()

            @subscribe { graph: @get 'name' }, (msg,reply,next,transmit) =>
                
                if not msg.source then msg.source = 'default'

                if not @sources[msg.source]
                    sourcenode = @sources[msg.source] = new DataSource name: msg.source
                    @connect sourcenode
                    sourcenode.msg {test:'msg'}

                    sourcenode.on 'change:max', (stream,streammax) =>
                        max = @get 'max'
                        #console.log "my max is #{max} and stream max is #{streammax}"
                        if streammax > max then @set max: streammax
                        if streammax is max then @set max: @max()
                    
                reply.end()
                transmit()
                
                @redraw()

            @on 'change:max', (self,value) ->
                window.plot = @plot
                
                #@plot.getOptions().yaxes[0].max = value;
                @hardredraw()

        max: -> getmax(_.map @sources, (source) -> source.get 'max')
        
        hardredraw: ->
            max = @get('max')
            max = (max / 10.0) * 11
            
            @plot = $.plot @graphdiv, @exportdata(), {
                series: { shadowSize: 0 },
                yaxis: { show: true, min: 0, max: max },
                xaxis: { show: true, min: 0, max: 100 },
                legend: { position: "sw" }
            }
            
        redraw: ->
            @plot.setData @exportdata()
            @plot.draw()
            
        exportdata: ->
            _.map @sources, (source) -> source.exportdata()
                        
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
            
            env.websocket.subscribe { graph: @name, add: true }, (msg,reply) => reply.end(); @push msg.add
            env.websocket.subscribe { graph: @name, change: true }, (msg,reply) => reply.end(); @change msg.change
            env.websocket.subscribe { graph: @name, maxlen: true }, (msg,reply,next) =>
                reply.end(); next()
                @maxlen = msg.maxlen
                @data.shift() while @data.length - 1 > @maxlen
                @redraw()

            env.websocket.subscribe { graph: @name, clear: true }, (msg,reply,next) =>
                reply.end(); next()
                @data = [ 0 ]

        redraw: ->
            @plot.setData([cook(@data)])
            @plot.draw()
            
        push: (value) ->
            @data.push(value)
            if @data.length - 1 > @maxlen then @data.shift()
            @redraw()

        change: (value) -> 
            @data.push( _.last(data) + value)
            if @data.length - 1 > @maxlen then @data.shift()
            @redraw()

    graphs = {}
    
    env.websocket.subscribe { graph: true }, (msg,reply,next,transmit) ->
        if not graphs[msg.graph]
            graph = graphs[msg.graph] = new Graph name: msg.graph
            console.log 'created new graph', msg.graph, graphs
            graph.connect env.websocket
            
        reply.end()
        next()
        transmit()
        
    callback()

