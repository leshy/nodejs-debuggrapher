dgram = require 'dgram'
helpers = require 'helpers'

message = new Buffer JSON.stringify { graph: 'heapUsed', maxlen: 20 }
client = dgram.createSocket "udp4"
client.send message, 0, message.length, 41234, "localhost", (err, bytes) -> client.close()
