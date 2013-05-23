crypto = require 'crypto'
async = require 'async'
_ = require 'underscore'
Backbone = require 'backbone4000'

mongodb = require 'mongodb'
http = require 'http'
express = require 'express'
ejslocals = require 'ejs-locals'

logger = require 'logger'
helpers = require 'helpers'

decorators = require 'decorators'
decorate = decorators.decorate
comm = require 'comm/serverside'

dgram = require 'dgram'

settings = 
    db:
        name: 'logger'
        host: 'localhost'
        port: 27017
        
    port: 3334
        
    cookiesecret: 'eTkj6vB53WgwwMWXqnOsoWvnQkQ692UmsNAgtoU+'

    express:
        static: __dirname + '/static'
        views: __dirname + '/ejs'

env = {} 

env.settings = helpers.extend settings, require('./settings').settings

initLogger = (env,callback) ->
    env.logger = new logger.logger()
    env.consoleLogger = new logger.consoleLogger()
    env.logger.pass()
    env.logger.connect(env.consoleLogger)
    env.log = env.logger.log.bind(env.logger)

    env.logres = (name, callback) ->
        (err,data) -> 
            if (err)
                env.log name + ': ' + err, {error: err}, 'init', 'fail'
            else
                env.log name + "...", {}, 'init', 'ok'
            callback(err,data)
        
    env.log('logger...', {}, 'init', 'ok')
    callback()

initDb = (env,callback) ->
    env.db = new mongodb.Db env.settings.db.name, new mongodb.Server(env.settings.db.host, env.settings.db.port), safe: true
    env.db.open callback

initExpress = (env,callback) ->
    env.app = app = express()
    
    app.configure ->
        app.engine 'ejs', ejslocals
        app.set 'view engine', 'ejs'
        app.set 'views', env.settings.express.views
        app.use express.favicon()
        app.use express.bodyParser()
        app.use express.methodOverride()
        app.use express.cookieParser()

        # /node_modules/connect/node_modules/crc/lib/crc.js
        # 
        # there is a bug in crc16 module,
        # it checks for global.window object and concludes that its running in a browser and not node
        # so it doesn't use exports object to expose its functions..
        # I've patched it now, but on the next install it will fail again.
        # 
        # some other module is creating global.window for some reason, which is a refenrence to global
        
        app.use app.router
        app.use express.static(env.settings.express.static)
        app.use (err, req, res, next) ->
            env.log 'web request error', { stack: err.stack }, 'error', 'http'
            res.send 500, 'BOOOM!'
    
    env.server = http.createServer env.app
    env.server.listen env.settings.port
    env.log 'http server listening at ' + env.settings.port, {}, 'init', 'http'
    callback undefined, true    


initRoutes = (env,callback) ->
    logreq = (req,res,next) ->
        host = req.socket.remoteAddress
        if host is "127.0.0.1" then if forwarded = req.headers['x-forwarded-for'] then host = forwarded
        env.log req.originalUrl, { host: host, headers: req.headers, method: req.method }, 'http', req.method, host
        next()

    env.app.get '*', logreq
    env.app.post '*', logreq
    
    env.app.get '/', (req,res) ->
        res.render 'index', { title: 'logger' }
    callback()

    env.app.get '/pic/*', (req,res,next) ->
        res.setHeader("Cache-Control", "public, max-age=1000"); # this is temporary, should think about caching some more later.
        next()
        

initWebsockets = (env,callback) ->
    env.websocket = new comm.WebsocketServer http: env.server, realm: 'web', name: 'websocket', options: { notransmit: true, socketio: { log: false } }
    
    env.websocket.pass()

    env.websocket.listen (client) ->
        socket = client.get 'socket'
        id = socket.id
        host = socket.handshake.address.address
        env.log '', { id: socket.id, host: host }, 'socketio', 'connected', host, id


    callback undefined, true

initListener = (env,callback) ->
    server = env.loglistener = dgram.createSocket 'udp4'

    server.on "message", (msg, rinfo) -> 
        env.websocket.msg new comm.Msg JSON.parse(msg)

    server.on "listening", -> 
        address = server.address();
        console.log("server listening " +
        address.address + ":" + address.port);
        callback()
        
    server.bind(41234);

initCollections = (env,callback) ->
    ###

    env.streams = new comm.MongoCollectionNode db: env.db, collection: 'streams'
    env.streams.defineModel 'stream', comm.MsgNode
        minspacing = 1000
    
        initialize: ->
            @collection = env.db.collection @get('name')
            
        in: (data) -> true
            
        out: (timefrom, timeto, callback) ->

            maxpoints = 50
                        
            @collection.find { time: { '$gt': timefrom, '$lt': timeto }}, (err,cursor) -> 
                #cursor.count (err,count) ->
    ###            
        
    callback()


exports.init = (env,callback) ->
    async.auto 
        logger: (callback) -> initLogger(env,callback)
        listener: [ 'websockets', 'logger', (callback) -> initListener env, env.logres('UDP listener',callback) ]
        database: [ 'logger', (callback) -> initDb env, env.logres('database',callback) ]
        express: [ 'database', 'logger', (callback) -> initExpress env, env.logres('express',callback) ]
        routes: [ 'express', (callback) -> initRoutes env, env.logres('routes',callback) ]
        websockets: [ 'express', (callback) -> initWebsockets env, env.logres('websockets',callback) ]
        callback

exports.init env, -> true

